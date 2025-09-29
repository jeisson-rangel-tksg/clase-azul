public with sharing class AccountMergeFlowAction {
    // ===== Flow I/O =====
    public class Request {
        @InvocableVariable(required=true)
        public Id mainAccountId;

        @InvocableVariable(required=true)
        public List<Id> duplicateAccountIds;
    }

    // --- test seam for locks ---
    @TestVisible private static Boolean TEST_FORCE_MAIN_LOCKED = false;
    @TestVisible private static Set<Id> TEST_FORCE_LOCKED_IDS = new Set<Id>();
    @TestVisible static void testResetLocks() {
        TEST_FORCE_MAIN_LOCKED = false;
        TEST_FORCE_LOCKED_IDS.clear();
    }

    public class Result {
        @InvocableVariable public Id mainAccountId;
        @InvocableVariable public List<Id> mergedAccountIds;
        @InvocableVariable public List<Id> skippedAccountIds;
        @InvocableVariable public List<String> messages;
        @InvocableVariable public Boolean success;
    }

    @InvocableMethod(
        label='Merge Accounts (Main + Dupes)'
        description='Merges duplicates into the provided main Account. Skips locked or mismatched-type records, with detailed logs.'
    )
    public static List<Result> mergeAccounts(List<Request> inputs) {
        List<Result> out = new List<Result>();

        if (inputs == null || inputs.isEmpty()) {
            System.debug(LoggingLevel.WARN, '[MergeFlow] No inputs received.');
            return out;
        }

        Integer reqIndex = 0;

        for (Request req : inputs) {
            reqIndex = reqIndex + 1;

            Result res = new Result();
            res.mergedAccountIds = new List<Id>();
            res.skippedAccountIds = new List<Id>();
            res.messages = new List<String>();
            res.success = false;
            res.mainAccountId = (req == null) ? null : req.mainAccountId;

            System.debug(LoggingLevel.INFO, '[MergeFlow][' + reqIndex + '] Start. Raw main=' + res.mainAccountId + ', raw dupes=' + String.valueOf(req != null ? req.duplicateAccountIds : null));

            if (req == null) {
                res.messages.add('Request was null.');
                System.debug(LoggingLevel.ERROR, '[MergeFlow][' + reqIndex + '] Request was null.');
                out.add(res);
                continue;
            }
            if (req.mainAccountId == null) {
                res.messages.add('mainAccountId is required.');
                System.debug(LoggingLevel.ERROR, '[MergeFlow][' + reqIndex + '] mainAccountId is required.');
                out.add(res);
                continue;
            }

            // Normalize dupes (distinct, no nulls, no self)
            Set<Id> dupeSet = new Set<Id>();
            if (req.duplicateAccountIds != null) {
                for (Id d : req.duplicateAccountIds) {
                    if (d != null && d != req.mainAccountId) {
                        dupeSet.add(d);
                    } else {
                        if (d == null) {
                            System.debug(LoggingLevel.DEBUG, '[MergeFlow][' + reqIndex + '] Skipping null dupe Id.');
                        } else if (d == req.mainAccountId) {
                            System.debug(LoggingLevel.DEBUG, '[MergeFlow][' + reqIndex + '] Skipping self Id ' + d);
                        }
                    }
                }
            }
            System.debug(LoggingLevel.INFO, '[MergeFlow][' + reqIndex + '] Normalized dupes=' + dupeSet);

            if (dupeSet.isEmpty()) {
                res.messages.add('No duplicate Account Ids to merge.');
                res.success = true;
                System.debug(LoggingLevel.WARN, '[MergeFlow][' + reqIndex + '] No dupes after normalization. Done.');
                out.add(res);
                continue;
            }

            // Fetch main record/type
            Account main;
            try {
                main = [
                    SELECT Id, IsPersonAccount
                    FROM Account
                    WHERE Id = :req.mainAccountId
                    LIMIT 1
                ];
            } catch (Exception eMain) {
                String msg = 'Failed to query main Account: ' + eMain.getMessage();
                res.messages.add(msg);
                System.debug(LoggingLevel.ERROR, '[MergeFlow][' + reqIndex + '] ' + msg);
                out.add(res);
                continue;
            }
            System.debug(LoggingLevel.INFO, '[MergeFlow][' + reqIndex + '] Main ' + main.Id + ' IsPersonAccount=' + String.valueOf(main.IsPersonAccount));

            // Fetch dupes (for IsPersonAccount)
            Map<Id, Account> dupMap = new Map<Id, Account>();
            try {
                dupMap = new Map<Id, Account>([
                    SELECT Id, IsPersonAccount
                    FROM Account
                    WHERE Id IN :dupeSet
                ]);
            } catch (Exception eDupQ) {
                String msg = 'Failed to query dupes: ' + eDupQ.getMessage();
                res.messages.add(msg);
                System.debug(LoggingLevel.ERROR, '[MergeFlow][' + reqIndex + '] ' + msg);
                out.add(res);
                continue;
            }

            // Keep only dupes that match main's type (person vs business)
            List<Id> sameTypeDupes = new List<Id>();
            for (Id d : dupeSet) {
                Account da = dupMap.get(d);
                if (da == null) {
                    res.skippedAccountIds.add(d);
                    String msg = 'Skipped ' + String.valueOf(d) + ' (not found).';
                    res.messages.add(msg);
                    System.debug(LoggingLevel.WARN, '[MergeFlow][' + reqIndex + '] ' + msg);
                    continue;
                }
                if (da.IsPersonAccount != main.IsPersonAccount) {
                    res.skippedAccountIds.add(d);
                    String msg2 = 'Skipped ' + da.Id + ' (mismatched account type; main IsPerson='
                                  + String.valueOf(main.IsPersonAccount) + ', dupe IsPerson=' + String.valueOf(da.IsPersonAccount) + ').';
                    res.messages.add(msg2);
                    System.debug(LoggingLevel.WARN, '[MergeFlow][' + reqIndex + '] ' + msg2);
                    continue;
                }
                sameTypeDupes.add(da.Id);
            }
            System.debug(LoggingLevel.INFO, '[MergeFlow][' + reqIndex + '] Same-type dupes=' + sameTypeDupes);

            if (sameTypeDupes.isEmpty()) {
                res.messages.add('No same-type dupes to merge (person vs business mismatch).');
                res.success = true;
                System.debug(LoggingLevel.WARN, '[MergeFlow][' + reqIndex + '] No same-type dupes. Done.');
                out.add(res);
                continue;
            }

            // Lock check on master (test seam aware)
            Boolean masterLocked = false;
            try {
                if (Test.isRunningTest() && TEST_FORCE_MAIN_LOCKED) {
                    masterLocked = true;
                } else {
                    masterLocked = Approval.isLocked(main.Id);
                }
            } catch (Exception eLockMain) {
                masterLocked = false;
                System.debug(LoggingLevel.DEBUG, '[MergeFlow][' + reqIndex + '] Approval.isLocked(main) threw: ' + eLockMain.getMessage());
            }
            System.debug(LoggingLevel.INFO, '[MergeFlow][' + reqIndex + '] Main locked=' + String.valueOf(masterLocked));

            if (masterLocked) {
                String msg = 'Main Account is locked; cannot merge.';
                res.messages.add(msg);
                System.debug(LoggingLevel.WARN, '[MergeFlow][' + reqIndex + '] ' + msg);
                out.add(res);
                continue;
            }

            // Remove locked dupes
            List<Id> unlockedDupes = new List<Id>();
            for (Id d : sameTypeDupes) {
                Boolean locked = false;
                try {
                    if (Test.isRunningTest() && TEST_FORCE_LOCKED_IDS.contains(d)) {
                        locked = true;
                    } else {
                        locked = Approval.isLocked(d);
                    }
                } catch (Exception e2) {
                    locked = false;
                    System.debug(LoggingLevel.DEBUG, '[MergeFlow][' + reqIndex + '] Approval.isLocked(' + d + ') threw: ' + e2.getMessage());
                }
                if (!locked) {
                    unlockedDupes.add(d);
                } else {
                    res.skippedAccountIds.add(d);
                    String msg3 = 'Skipped ' + d + ' (locked/pending approval).';
                    res.messages.add(msg3);
                    System.debug(LoggingLevel.WARN, '[MergeFlow][' + reqIndex + '] ' + msg3);
                }
            }
            System.debug(LoggingLevel.INFO, '[MergeFlow][' + reqIndex + '] Unlocked dupes=' + unlockedDupes);

            if (unlockedDupes.isEmpty()) {
                res.messages.add('All same-type dupes are locked; nothing to merge.');
                System.debug(LoggingLevel.WARN, '[MergeFlow][' + reqIndex + '] All dupes locked. Done.');
                out.add(res);
                continue;
            }

            // Merge in rounds (≤ 2 dupes per call). Use Database.merge to capture MergeResult(s).
            Integer i = 0;
            while (i < unlockedDupes.size()) {
                List<Account> chunk = new List<Account>();
                chunk.add(new Account(Id = unlockedDupes[i]));
                i = i + 1;

                if (i < unlockedDupes.size()) {
                    chunk.add(new Account(Id = unlockedDupes[i]));
                    i = i + 1;
                }

                System.debug(LoggingLevel.INFO, '[MergeFlow][' + reqIndex + '] Merging chunk into ' + main.Id + ' -> dupes=' + chunk);

                try {
                    Account masterStub = new Account(Id = main.Id);

                    if (chunk.size() == 1) {
                        // one loser
                        Database.MergeResult mr = Database.merge(masterStub, chunk[0]);

                        if (mr == null) {
                            String m = 'MergeResult is null (unexpected).';
                            res.messages.add(m);
                            System.debug(LoggingLevel.ERROR, '[MergeFlow][' + reqIndex + '] ' + m);
                        } else {
                            if (mr.isSuccess()) {
                                List<Id> losersMerged = mr.getMergedRecordIds();
                                if (losersMerged != null && !losersMerged.isEmpty()) {
                                    for (Id L : losersMerged) {
                                        res.mergedAccountIds.add(L);
                                    }
                                }
                                System.debug(LoggingLevel.INFO, '[MergeFlow][' + reqIndex + '] Merge OK. Master=' + mr.getId() + ' losers=' + losersMerged);
                            } else {
                                Database.Error[] errs = mr.getErrors();
                                if (errs != null && errs.size() > 0) {
                                    for (Database.Error e : errs) {
                                        String em = 'Merge error: status=' + String.valueOf(e.getStatusCode())
                                                  + ' msg=' + e.getMessage()
                                                  + ' fields=' + String.valueOf(e.getFields());
                                        res.messages.add(em);
                                        System.debug(LoggingLevel.ERROR, '[MergeFlow][' + reqIndex + '] ' + em);
                                    }
                                } else {
                                    res.messages.add('Merge failed with unknown error.');
                                    System.debug(LoggingLevel.ERROR, '[MergeFlow][' + reqIndex + '] Merge failed (no error details).');
                                }
                            }
                        }
                    } else {
                        // two losers in one call
                        List<Account> losers = new List<Account>();
                        losers.add(chunk[0]);
                        losers.add(chunk[1]);

                        List<Database.MergeResult> mrs = Database.merge(masterStub, losers);

                        if (mrs == null || mrs.isEmpty()) {
                            String m = 'MergeResults list is null/empty (unexpected).';
                            res.messages.add(m);
                            System.debug(LoggingLevel.ERROR, '[MergeFlow][' + reqIndex + '] ' + m);
                        } else {
                            for (Database.MergeResult r : mrs) {
                                if (r == null) {
                                    System.debug(LoggingLevel.ERROR, '[MergeFlow][' + reqIndex + '] Null MergeResult entry.');
                                    continue;
                                }
                                if (r.isSuccess()) {
                                    List<Id> losersMerged = r.getMergedRecordIds();
                                    if (losersMerged != null && !losersMerged.isEmpty()) {
                                        for (Id L : losersMerged) {
                                            res.mergedAccountIds.add(L);
                                        }
                                    }
                                    System.debug(LoggingLevel.INFO, '[MergeFlow][' + reqIndex + '] Merge OK. Master=' + r.getId() + ' losers=' + losersMerged);
                                } else {
                                    Database.Error[] errs = r.getErrors();
                                    if (errs != null && errs.size() > 0) {
                                        for (Database.Error e : errs) {
                                            String em = 'Merge error: status=' + String.valueOf(e.getStatusCode())
                                                      + ' msg=' + e.getMessage()
                                                      + ' fields=' + String.valueOf(e.getFields());
                                            res.messages.add(em);
                                            System.debug(LoggingLevel.ERROR, '[MergeFlow][' + reqIndex + '] ' + em);
                                        }
                                    } else {
                                        res.messages.add('Merge failed with unknown error (list case).');
                                        System.debug(LoggingLevel.ERROR, '[MergeFlow][' + reqIndex + '] Merge failed (no error details, list case).');
                                    }
                                }
                            }
                        }
                    }
                } catch (DmlException dmle) {
                    String em = 'DML exception during merge: ' + dmle.getMessage();
                    res.messages.add(em);
                    System.debug(LoggingLevel.ERROR, '[MergeFlow][' + reqIndex + '] ' + em);
                } catch (Exception ex) {
                    String em2 = 'Unexpected exception during merge: ' + ex.getMessage();
                    res.messages.add(em2);
                    System.debug(LoggingLevel.ERROR, '[MergeFlow][' + reqIndex + '] ' + em2);
                }
            }

            res.success = true;
            System.debug(LoggingLevel.INFO, '[MergeFlow][' + reqIndex + '] Done. Merged=' + res.mergedAccountIds + ' Skipped=' + res.skippedAccountIds + ' Messages=' + res.messages);
            out.add(res);
        }

        return out;
    }
}
