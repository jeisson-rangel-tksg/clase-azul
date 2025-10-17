@IsTest
private class DupClusterSvcTest {
    @IsTest
    static void pick_main_by_owner() {
        User normal = makeUser('normal1@example.test');
        User integration = makeUser('integration1@example.test');
        User approver = makeUser('approver1@example.test');

        DupSettings cfg = new DupSettings();
        cfg.integrationOwnerId = integration.Id;
        cfg.tieBreaker = 'Oldest';
        cfg.nextApproverUsername = approver.Username;
        DupSettings.setTestOverride(cfg);

        Account a = newPA('Alice','Main','alice@test.local'); a.OwnerId = normal.Id;
        Account b = newPA('Bob','Dupe','alice@test.local');   b.OwnerId = integration.Id;
        Account c = newPA('Cara','Dupe','alice@test.local');  c.OwnerId = integration.Id;
        insert new List<Account>{ a, b, c };

        DupScanSvc.DupResult r = new DupScanSvc.DupResult(a);
        r.dupes.add(b); r.dupes.add(c);

        List<DupClusterSvc.ClusterDecision> d =
            DupClusterSvc.decideMainsFromScan(new List<DupScanSvc.DupResult>{ r }, DupSettings.load());

        System.assertEquals(1, d.size());
        System.assertEquals(a.Id, d[0].mainId);

        DupSettings.clearTestOverride();
    }

    @IsTest
    static void newest_tiebreaker_uses_lowestId_when_equal_dates() {
        User integration = makeUser('integration2@example.test');

        Account a = newPA('A','One','tb@test.local'); a.OwnerId = integration.Id;
        Account b = newPA('B','Two','tb@test.local'); b.OwnerId = integration.Id;
        insert new List<Account>{ a, b };

        // Misma fecha → fallback a menor Id
        Datetime t = Datetime.now().addMinutes(-5);
        Test.setCreatedDate(a.Id, t);
        Test.setCreatedDate(b.Id, t);

        DupScanSvc.DupResult r = new DupScanSvc.DupResult(a);
        r.dupes.add(b);

        DupSettings cfg = new DupSettings();
        cfg.integrationOwnerId = integration.Id;
        cfg.tieBreaker = 'Newest';
        cfg.nextApproverUsername = null;

        List<DupClusterSvc.ClusterDecision> d =
            DupClusterSvc.decideMainsFromScan(new List<DupScanSvc.DupResult>{ r }, cfg);

        System.assertEquals(1, d.size());
        Id expected = (String.valueOf(a.Id) < String.valueOf(b.Id)) ? a.Id : b.Id;
        System.assertEquals(expected, d[0].mainId);
    }

    private static User makeUser(String username) {
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        Integer rnd = Math.mod(Crypto.getRandomInteger(), 1000); if (rnd < 0) rnd = -rnd;
        String alias = ('utl' + String.valueOf(rnd)).left(8);
        User u = new User(
            Username=username, Email=username, Alias=alias, LastName='Test',
            TimeZoneSidKey='America/Los_Angeles', LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8', LanguageLocaleKey='en_US', ProfileId=p.Id
        ); insert u; return u;
    }
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
}
