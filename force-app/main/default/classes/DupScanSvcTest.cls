@IsTest
private class DupScanSvcTest {

    @IsTest
    static void threshold_strict_returns_empty() {
        Account a = newPA('Ana','Alpha','ana.alpha@test.local');
        Account b = newPA('Beto','Beta','otrocorreo@test.local');
        insert new List<Account>{ a, b };

        DupScanSvc.TEST_BYPASS_DUP_API = true;
        DupScanSvc.TEST_CANDIDATES.put(a.Id, new List<Account>{ b });

        List<DupScanSvc.DupResult> out =
            DupScanSvc.filterDupesByEmailDistance(new List<Account>{ a, b }, 1, new Set<String>());
        System.assertEquals(0, out.size());
        DupScanSvc.testReset();
    }

    @IsTest
    static void blank_emails_are_skipped_via_override() {
        Account src  = newPA('Sin','Email','placeholder.src@test.local');
        Account cand = newPA('Candi','Date','placeholder.cand@test.local');
        insert new List<Account>{ src, cand };

        DupScanSvc.TEST_BYPASS_DUP_API = true;
        DupScanSvc.TEST_CANDIDATES.put(src.Id, new List<Account>{ cand });

        // simulate blank emails without violating org validation
        DupScanSvc.TEST_EMAIL_OVERRIDE.put(src.Id, null);
        DupScanSvc.TEST_EMAIL_OVERRIDE.put(cand.Id, '   ');

        List<DupScanSvc.DupResult> out =
            DupScanSvc.filterDupesByEmailDistance(new List<Account>{ src, cand }, 2, new Set<String>());
        System.assertEquals(0, out.size(), 'source with blank email ⇒ no results');
        DupScanSvc.testReset();
    }

    @IsTest
    static void empty_scope_returns_empty() {
        List<DupScanSvc.DupResult> out =
            DupScanSvc.filterDupesByEmailDistance(new List<Account>(), 2, new Set<String>());
        System.assertEquals(0, out.size(), 'empty scope ⇒ empty result');
    }

    @IsTest
    static void candidate_null_is_skipped_and_valid_kept() {
        Account src  = newPA('Ann','Alpha','usera@test.local');
        Account cand = newPA('Ann','Alpha','user.a@test.local'); // dist=1
        insert new List<Account>{ src, cand };

        DupScanSvc.TEST_BYPASS_DUP_API = true;
        DupScanSvc.TEST_CANDIDATES.put(src.Id, new List<Account>{ null, cand }); // null candidate included

        List<DupScanSvc.DupResult> out =
            DupScanSvc.filterDupesByEmailDistance(new List<Account>{ src, cand }, 2, new Set<String>());

        System.assertEquals(1, out.size(), 'one src yields dupes');
        System.assertEquals(1, out[0].dupes.size(), 'null candidate skipped, valid kept');
        System.assertEquals(cand.Id, out[0].dupes[0].Id);
        DupScanSvc.testReset();
    }

    @IsTest
    static void datacloud_path_chunking_smoke_two_chunks() {
        // hit the non-bypass path to cover the chunking loop (no dupes expected)
        List<Account> many = new List<Account>();
        for (Integer i = 0; i < 55; i++) { // >50 to force two chunks
            many.add(newPA('User',''+i, 'u'+i+'@chunk.test.local'));
        }
        insert many;

        // ensure bypass is OFF
        DupScanSvc.testReset(); // clears flags (TEST_BYPASS_DUP_API=false)

        // rule filter provided (even if org rules return zero results)
        Set<String> ruleFilter = new Set<String>{ 'NonExistingRule__c' };

        List<DupScanSvc.DupResult> out =
            DupScanSvc.filterDupesByEmailDistance(many, 0, ruleFilter);

        // We only care that it ran without exception; likely no results
        System.assertEquals(0, out.size(), 'no dupes expected in chunking smoke');
    }

    // -------- helper --------
    private static Account newPA(String fn, String ln, String email) {
        Account x = new Account();
        x.FirstName = fn; x.LastName = ln; x.PersonEmail = email;
        x.AccountSource       = CLA_FormConstants.DEFAULT_ACCOUNT_SOURCE;
        x.CLA_Fuente__c       = CLA_FormConstants.DEFAULT_SOURCE;
        x.CLA_SubCategory__c  = CLA_FormConstants.DEFAULT_SUBCATEGORY;
        x.RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get(CLA_FormConstants.RECORD_TYPE_PERSON_ACCOUNT).getRecordTypeId();
        return x;
    }
}
