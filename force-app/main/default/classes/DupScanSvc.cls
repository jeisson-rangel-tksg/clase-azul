public with sharing class DupScanSvc {
    public class DupResult {
        public Account source;
        public List<Account> dupes;

        public DupResult(Account source) {
            this.source = source;
            this.dupes = new List<Account>();
        }
    }

    private static final Integer DUP_API_LIMIT = 50; // findDuplicatesByIds max per call.

    // --- test seam (used only in tests) ---
    @TestVisible private static Map<Id, String> TEST_EMAIL_OVERRIDE = new Map<Id, String>();
    @TestVisible private static Boolean TEST_BYPASS_DUP_API = false;
    @TestVisible private static Map<Id, List<Account>> TEST_CANDIDATES = new Map<Id, List<Account>>();

    @TestVisible
    static void testReset() {
        TEST_BYPASS_DUP_API = false;
        TEST_CANDIDATES.clear();
        TEST_EMAIL_OVERRIDE.clear();
    }

    public static List<DupResult> filterDupesByEmailDistance(List<Account> scope, Integer threshold, Set<String> ruleDevNames) {
        Map<Id, String> srcEmailById = new Map<Id, String>();
        Map<Id, Account> srcById = new Map<Id, Account>();

        for (Account a : scope) {
            if (a == null) {
                continue;
            }
            String raw = emailFor(a);
            String norm = normalizeEmail(raw);
            srcEmailById.put(a.Id, norm);
            srcById.put(a.Id, a);
        }

        List<Id> allIds = new List<Id>(srcEmailById.keySet());
        if (allIds.isEmpty()) {
            return new List<DupResult>();
        }

        Map<Id, List<Account>> candidatesBySrc = new Map<Id, List<Account>>();

        if (Test.isRunningTest() && TEST_BYPASS_DUP_API) {
            // Use test-supplied candidates; do not call Datacloud in tests
            for (Id srcId : allIds) {
                if (TEST_CANDIDATES.containsKey(srcId)) {
                    candidatesBySrc.put(srcId, new List<Account>(TEST_CANDIDATES.get(srcId)));
                }
            }
        } else {
            // --- real path: Datacloud.FindDuplicatesByIds in 50-id chunks ---
            Integer startIdx = 0;
            while (startIdx < allIds.size()) {
                Integer endIdx = startIdx + DUP_API_LIMIT;
                if (endIdx > allIds.size()) {
                    endIdx = allIds.size();
                }
                List<Id> chunk = new List<Id>();
                for (Integer i = startIdx; i < endIdx; i++) {
                    chunk.add(allIds[i]);
                }
                startIdx = endIdx;
                if (chunk.isEmpty()) {
                    continue;
                }

                List<Datacloud.FindDuplicatesResult> results = Datacloud.FindDuplicatesByIds.findDuplicatesByIds(chunk);
                for (Integer i = 0; i < results.size(); i++) {
                    Id src = chunk[i];
                    Datacloud.FindDuplicatesResult r = results[i];
                    List<Datacloud.DuplicateResult> dups = r.getDuplicateResults();
                    for (Datacloud.DuplicateResult dr : dups) {
                        if (ruleDevNames != null && !ruleDevNames.isEmpty()) {
                            String ruleName = dr.getDuplicateRule();
                            if (!ruleDevNames.contains(ruleName)) {
                                continue;
                            }
                        }
                        for (Datacloud.MatchResult mr : dr.getMatchResults()) {
                            for (Datacloud.MatchRecord rec : mr.getMatchRecords()) {
                                SObject sobj = rec.getRecord();
                                if (sobj instanceof Account) {
                                    if (!candidatesBySrc.containsKey(src)) {
                                        candidatesBySrc.put(src, new List<Account>());
                                    }
                                    candidatesBySrc.get(src).add((Account)sobj);
                                }
                            }
                        }
                    }
                }
            }
        }

        List<DupResult> out = new List<DupResult>();
        for (Id srcId : candidatesBySrc.keySet()) {
            String srcEmail = srcEmailById.get(srcId);
            if (String.isBlank(srcEmail)) {
                continue;
            }

            DupResult dr = new DupResult(srcById.get(srcId));
            List<Account> cands = candidatesBySrc.get(srcId);

            for (Account cand : cands) {
                String candEmail = normalizeEmail(emailFor(cand));
                if (String.isBlank(candEmail)) {
                    continue;
                }

                Integer dist = srcEmail.getLevenshteinDistance(candEmail); // :contentReference[oaicite:3]{index=3}
                if (dist <= threshold) {
                    dr.dupes.add(cand);
                }
            }

            if (!dr.dupes.isEmpty()) {
                out.add(dr);
            }
        }
        return out;
    }

    private static String emailFor(Account a) {
        if (a == null) {
            return null;
        }
        if (Test.isRunningTest() && TEST_EMAIL_OVERRIDE.containsKey(a.Id)) {
            return TEST_EMAIL_OVERRIDE.get(a.Id);
        }
        return a.PersonEmail;
    }

    private static String normalizeEmail(String s) {
        if (s == null) {
            return null;
        }
        return s.trim().toLowerCase();
    }
}
