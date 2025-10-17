@IsTest
private class AcctDupScanBatchTest {
    @IsTest
    static void executes_and_stamps_with_test_hook() {
        User integration = makeUser('integration4@example.test');
        User normal = makeUser('normal4@example.test');

        DupSettings cfg = new DupSettings();
        cfg.integrationOwnerId = integration.Id;
        cfg.tieBreaker = 'Oldest';
        cfg.nextApproverUsername = null;
        DupSettings.setTestOverride(cfg);

        Account a = newPA('Ana','Main','dup@test.local'); a.OwnerId = normal.Id;
        Account b = newPA('Ben','Dupe','dup@test.local'); b.OwnerId = integration.Id;
        insert new List<Account>{ a, b };

        DupScanSvc.TEST_BYPASS_DUP_API = true;
        DupScanSvc.TEST_CANDIDATES.put(a.Id, new List<Account>{ b });

        AcctDupScanBatch bch = new AcctDupScanBatch(2, new Set<String>(), AcctDupScanBatch.ScanMode.CreatedToday);

        Test.startTest();
        Database.executeBatch(bch, 50);
        Test.stopTest();

        Account aA = [SELECT IsMainAccount__c, Account_Status__c FROM Account WHERE Id=:a.Id];
        Account bA = [SELECT Principal_Account__c FROM Account WHERE Id=:b.Id];
        System.assertEquals(true, aA.IsMainAccount__c);
        System.assertEquals('Pending', aA.Account_Status__c);
        System.assertEquals(a.Id, bA.Principal_Account__c);

        DupSettings.clearTestOverride();
        DupScanSvc.testReset();
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
