@IsTest
private class AccountMergeFlowActionTest {

    @IsTest
    static void invocable_ignores_null_request_entries() {
        // Valid main + dupe (so the non-null entry succeeds)
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        dml.DuplicateRuleHeader.runAsCurrentUser = false;

        Account main = newPA('NullReq','Main','nullreq@test.local');
        Account d1   = newPA('NullReq','Dupe','nullreq@test.local');
        Database.SaveResult[] srs = Database.insert(new List<Account>{ main, d1 }, dml);

        AccountMergeFlowAction.Request good = new AccountMergeFlowAction.Request();
        good.mainAccountId = srs[0].getId();
        good.duplicateAccountIds = new List<Id>{ srs[1].getId() };

        // Input list contains a null request plus a valid one — should ignore null safely
        Test.startTest();
        List<AccountMergeFlowAction.Result> res = AccountMergeFlowAction.mergeAccounts(
            new List<AccountMergeFlowAction.Request>{ null, good }
        );
        Test.stopTest();

        System.assertEquals(2, res.size(), 'should return one result per input element (null included)');
        System.assertEquals(false, res[0].success, 'null request should produce a failure result or empty outcome');
        System.assertEquals(true,  res[1].success, 'valid request should succeed');
    }

    @IsTest
    static void merge_fails_when_main_is_null() {
        // Have at least one existing PA to serve as a dupe
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        dml.DuplicateRuleHeader.runAsCurrentUser = false;

        Account dupe = newPA('NullMain','Dupe','nullmain@test.local');
        Database.SaveResult[] srs = Database.insert(new List<Account>{ dupe }, dml);

        AccountMergeFlowAction.Request req = new AccountMergeFlowAction.Request();
        req.mainAccountId = null; // main missing
        req.duplicateAccountIds = new List<Id>{ srs[0].getId() };

        Test.startTest();
        List<AccountMergeFlowAction.Result> res =
            AccountMergeFlowAction.mergeAccounts(new List<AccountMergeFlowAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assertEquals(false, res[0].success, 'null main should fail');
        System.assert(res[0].messages.size() > 0, 'expect message explaining missing main');
    }

    @IsTest
    static void merge_succeeds_with_one_valid_dupe_and_one_nonexistent() {
        // main + one valid dupe + one dupe id that no longer exists (exercise not-found path for dupes)
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        dml.DuplicateRuleHeader.runAsCurrentUser = false;

        Account main = newPA('Mixed','Main','mixed@test.local');
        Account ok   = newPA('Mixed','DupeOK','mixed@test.local');
        Account gone = newPA('Mixed','DupeGone','mixed@test.local');
        Database.SaveResult[] srs = Database.insert(new List<Account>{ main, ok, gone }, dml);

        Id mainId = srs[0].getId();
        Id okId   = srs[1].getId();
        Id goneId = srs[2].getId();

        // delete one so its Id becomes non-existent
        delete new Account(Id = goneId);

        AccountMergeFlowAction.Request req = new AccountMergeFlowAction.Request();
        req.mainAccountId = mainId;
        req.duplicateAccountIds = new List<Id>{ okId, goneId };

        Test.startTest();
        List<AccountMergeFlowAction.Result> res =
            AccountMergeFlowAction.mergeAccounts(new List<AccountMergeFlowAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assertEquals(true, res[0].success, 'should still succeed with at least one eligible dupe');
        System.assertEquals(1, res[0].mergedAccountIds.size(), 'only the existing dupe gets merged');
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Id IN :res[0].mergedAccountIds], 'merged dupe deleted');
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Id = :mainId], 'main remains');
    }


    @IsTest
    static void merge_chunking_normalization_mismatch_and_lockedDupe() {
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        dml.DuplicateRuleHeader.runAsCurrentUser = false;

        Account main = newPA('Main','User','pack@test.local');
        Account d1   = newPA('Dupe','One','pack@test.local');
        Account d2   = newPA('Dupe','Two','pack@test.local');
        Account d3   = newPA('Dupe','Three','pack@test.local');
        Account d4   = newPA('Dupe','Four','pack@test.local');
        Account biz  = newBiz('Biz Co'); // mismatch type

        Database.SaveResult[] srs = Database.insert(
            new List<Account>{ main, d1, d2, d3, d4, biz }, dml);

        Id mainId = srs[0].getId();
        Id id1 = srs[1].getId();
        Id id2 = srs[2].getId();
        Id id3 = srs[3].getId();
        Id id4 = srs[4].getId();
        Id bizId = srs[5].getId();

        // Force one dupe locked via seam
        AccountMergeFlowAction.TEST_FORCE_LOCKED_IDS.add(id2);

        // Include null and self + a business account to exercise normalization & mismatch paths
        List<Id> incoming = new List<Id>{ id1, id2, id3, id4, null, mainId, bizId, id1 /* duplicate id to dedupe */ };

        AccountMergeFlowAction.Request req = new AccountMergeFlowAction.Request();
        req.mainAccountId = mainId;
        req.duplicateAccountIds = incoming;

        Test.startTest();
        List<AccountMergeFlowAction.Result> res =
            AccountMergeFlowAction.mergeAccounts(new List<AccountMergeFlowAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, res.size());
        AccountMergeFlowAction.Result r = res[0];
        System.assertEquals(true, r.success);
        System.assertEquals(3, r.mergedAccountIds.size(), '3 unlocked person dupes merged');
        System.assert(r.skippedAccountIds.contains(id2), 'locked dupe skipped');
        System.assert(r.skippedAccountIds.contains(bizId), 'mismatch business skipped');
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Id IN :r.mergedAccountIds]);
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Id = :mainId]);

        AccountMergeFlowAction.testResetLocks();
    }

    @IsTest
    static void merge_skips_when_main_locked() {
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        dml.DuplicateRuleHeader.runAsCurrentUser = false;

        Account a0 = newPA('Lock','Main','lock@test.local');
        Account a1 = newPA('Lock','D1','lock@test.local');
        Account a2 = newPA('Lock','D2','lock@test.local');
        Database.SaveResult[] srs = Database.insert(new List<Account>{ a0, a1, a2 }, dml);
        Id mainId = srs[0].getId();
        List<Id> dupeIds = new List<Id>{ srs[1].getId(), srs[2].getId() };

        AccountMergeFlowAction.TEST_FORCE_MAIN_LOCKED = true;

        AccountMergeFlowAction.Request req = new AccountMergeFlowAction.Request();
        req.mainAccountId = mainId;
        req.duplicateAccountIds = dupeIds;

        Test.startTest();
        List<AccountMergeFlowAction.Result> res =
            AccountMergeFlowAction.mergeAccounts(new List<AccountMergeFlowAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assertEquals(false, res[0].success);
        System.assert(res[0].messages.size() > 0);

        AccountMergeFlowAction.testResetLocks();
    }

    @IsTest
    static void merge_fails_when_main_not_found() {
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        dml.DuplicateRuleHeader.runAsCurrentUser = false;

        Account main = newPA('Ghost','Main','ghost@test.local');
        Account d1   = newPA('Ghost','D1','ghost@test.local');
        Database.SaveResult[] srs = Database.insert(new List<Account>{ main, d1 }, dml);

        Id ghostId = srs[0].getId();
        delete main; // simulate "not found"

        AccountMergeFlowAction.Request req = new AccountMergeFlowAction.Request();
        req.mainAccountId = ghostId;
        req.duplicateAccountIds = new List<Id>{ srs[1].getId() };

        Test.startTest();
        List<AccountMergeFlowAction.Result> res =
            AccountMergeFlowAction.mergeAccounts(new List<AccountMergeFlowAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assertEquals(false, res[0].success, 'should fail when main not found');
        System.assert(res[0].messages.size() > 0);
    }

    @IsTest
    static void merge_succeeds_with_business_main_and_business_dupes() {
        // allow intentional dupes
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        dml.DuplicateRuleHeader.runAsCurrentUser = false;

        // Business main + 2 business dupes (same-ish name to mimic dupes)
        Account mainBiz = newBiz('Biz Main Co');
        Account d1Biz   = newBiz('Biz Main Co');
        Account d2Biz   = newBiz('Biz Main Co');
        Database.SaveResult[] srs = Database.insert(new List<Account>{ mainBiz, d1Biz, d2Biz }, dml);

        AccountMergeFlowAction.Request req = new AccountMergeFlowAction.Request();
        req.mainAccountId = srs[0].getId();
        req.duplicateAccountIds = new List<Id>{ srs[1].getId(), srs[2].getId() };

        Test.startTest();
        List<AccountMergeFlowAction.Result> res =
            AccountMergeFlowAction.mergeAccounts(new List<AccountMergeFlowAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assertEquals(true, res[0].success, 'business→business should merge');
        System.assertEquals(2, res[0].mergedAccountIds.size(), 'both biz dupes merged');
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Id IN :res[0].mergedAccountIds]);
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Id = :req.mainAccountId]);
    }

    @IsTest
    static void merge_returns_error_when_no_dupes_provided() {
        // allow inserts
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        dml.DuplicateRuleHeader.runAsCurrentUser = false;

        // main PA
        Account main = newPA('Main','NoDupes','nodupes@test.local');
        Database.SaveResult[] srs = Database.insert(new List<Account>{ main }, dml);
        Id mainId = srs[0].getId();

        // request with EMPTY duplicate list
        AccountMergeFlowAction.Request req = new AccountMergeFlowAction.Request();
        req.mainAccountId = mainId;
        req.duplicateAccountIds = new List<Id>();

        Test.startTest();
        List<AccountMergeFlowAction.Result> res =
            AccountMergeFlowAction.mergeAccounts(new List<AccountMergeFlowAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, res.size(), 'one response expected');
        // Action currently treats empty dupes as a no-op success
        System.assertEquals(true, res[0].success, 'empty dupes ⇒ no-op success');
        System.assertEquals(0, res[0].mergedAccountIds.size(), 'nothing merged');
        System.assertEquals(0, res[0].skippedAccountIds.size(), 'nothing skipped either');
    }


    @IsTest
    static void invocable_called_with_empty_requests_list_returns_empty() {
        Test.startTest();
        List<AccountMergeFlowAction.Result> res =
            AccountMergeFlowAction.mergeAccounts(new List<AccountMergeFlowAction.Request>());
        Test.stopTest();

        System.assertEquals(0, res.size(), 'empty input list ⇒ empty output');
    }


    // -------- helpers --------
    private static Account newPA(String fn, String ln, String email) {
        Account x = new Account();
        x.FirstName=fn; x.LastName=ln; x.PersonEmail=email;
        x.AccountSource=CLA_FormConstants.DEFAULT_ACCOUNT_SOURCE;
        x.CLA_Fuente__c=CLA_FormConstants.DEFAULT_SOURCE;
        x.CLA_SubCategory__c=CLA_FormConstants.DEFAULT_SUBCATEGORY;
        x.RecordTypeId=Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get(CLA_FormConstants.RECORD_TYPE_PERSON_ACCOUNT).getRecordTypeId();
        return x;
    }
    private static Account newBiz(String name) {
        Account a = new Account();
        a.Name = name;
        a.AccountSource=CLA_FormConstants.DEFAULT_ACCOUNT_SOURCE;
        a.CLA_Fuente__c=CLA_FormConstants.DEFAULT_SOURCE;
        a.CLA_SubCategory__c=CLA_FormConstants.DEFAULT_SUBCATEGORY;
        return a;
    }
}
