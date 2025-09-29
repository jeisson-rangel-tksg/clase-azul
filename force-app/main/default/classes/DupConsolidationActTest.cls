@IsTest
private class DupConsolidationActTest {
    @IsTest
    static void stamps_main_and_dupes_pending() {
        User normal = makeUser('normal3@example.test');
        User integration = makeUser('integration3@example.test');
        User approver = makeUser('approver3@example.test');

        DupSettings cfg = new DupSettings();
        cfg.integrationOwnerId = integration.Id;
        cfg.tieBreaker = 'Oldest';
        cfg.nextApproverUsername = approver.Username;
        DupSettings.setTestOverride(cfg);

        Account a = newPA('Main','A','m@test.local'); a.OwnerId = normal.Id;
        Account b = newPA('Dupe','B','m@test.local'); b.OwnerId = integration.Id;
        insert new List<Account>{ a, b };

        DupScanSvc.DupResult r = new DupScanSvc.DupResult(a);
        r.dupes.add(b);

        List<DupClusterSvc.ClusterDecision> d =
            DupClusterSvc.decideMainsFromScan(new List<DupScanSvc.DupResult>{ r }, DupSettings.load());

        Test.startTest();
        DupConsolidationAct.stampAndSubmit(d);
        Test.stopTest();

        Map<Id, Account> m = new Map<Id, Account>([
            SELECT Id, IsMainAccount__c, Principal_Account__c, Account_Status__c
            FROM Account WHERE Id IN :new Set<Id>{ a.Id, b.Id }
        ]);
        System.assertEquals(true,  m.get(a.Id).IsMainAccount__c);
        System.assertEquals('Pending', m.get(a.Id).Account_Status__c);
        System.assertEquals(a.Id, m.get(b.Id).Principal_Account__c);

        DupSettings.clearTestOverride();
    }

    // helpers
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
