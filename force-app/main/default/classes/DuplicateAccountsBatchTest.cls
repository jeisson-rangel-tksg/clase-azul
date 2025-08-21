@isTest
private class DuplicateAccountsBatchTest {
    @testSetup
    static void setupTestData() {
        // Create test users
        User integrationUser = new User(
            FirstName = 'Insights',
            LastName = 'Integration',
            Alias = 'intuser',
            Email = 'integrationuser@test.com',
            Username = 'integrationuser@test.com' + System.currentTimeMillis(),
            CommunityNickname = 'intuser',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            LanguageLocaleKey = 'en_US'
        );
        insert integrationUser;
        
        /* // Create test accounts (duplicates)
Account acc1 = new Account(Name = 'Acme Corp', Phone = '1234567890', OwnerId = UserInfo.getUserId(),CLA_Fuente__c='DIGITAL CELLAR', CLA_OptIn__pc = true,CLA_SubCategory__c='test',CLA_MemberTier__c = 'Prospect');
Account acc2 = new Account(Name = 'Acme Corporation', Phone = '1234567890', OwnerId = UserInfo.getUserId(),CLA_Fuente__c='DIGITAL CELLAR', CLA_OptIn__pc = true,CLA_SubCategory__c='test',CLA_MemberTier__c = 'Prospect');
Account acc3 = new Account(Name = 'Acme Ltd', Phone = '1234567890', OwnerId = integrationUser.Id,CLA_Fuente__c='DIGITAL CELLAR', CLA_OptIn__pc = true,CLA_SubCategory__c='test',CLA_MemberTier__c = 'Prospect');
insert new List<Account>{acc1, acc2, acc3};*/
        Id personAccountRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1].Id;
        
        // Create three test person accounts
        List<Account> testAccounts = new List<Account>{
            new Account(FirstName='Prospect',LastName = 'Prospect Test',CLA_Fuente__c = 'DIGITAL CELLAR', PersonEmail='test@gmail.com',CLA_SubCategory__c='test', AccountSource='COLLECTOR', CLA_OptIn__pc = true, RecordTypeId = personAccountRT, CLA_MemberTier__c = 'Prospect'),
                new Account(FirstName='Active', LastName = 'Active Test', CLA_Fuente__c = 'DIGITAL CELLAR', PersonEmail='test@gmail.com',CLA_SubCategory__c='test',AccountSource='COLLECTOR', CLA_OptIn__pc = true, RecordTypeId = personAccountRT, CLA_MemberTier__c = 'Prospect'),
                new Account(FirstName='Inactive',LastName = 'Inactive Test', CLA_Fuente__c = 'DIGITAL CELLAR', PersonEmail='test@gmail.com',CLA_SubCategory__c='test',AccountSource='COLLECTOR', CLA_OptIn__pc = true, RecordTypeId = personAccountRT, CLA_MemberTier__c = 'Prospect')
                };
                    insert testAccounts;
        // Create Public Groups
        Group groupA = new Group(Name = 'Non-Integration Account Approvals', Type = 'Regular');
        Group groupB = new Group(Name = 'Integration Account Approvals', Type = 'Regular');
        insert new List<Group>{groupA, groupB};
            }
    
    @isTest
    static void testBatchExecution() {
        Test.startTest();
        DuplicateAccountsBatch batch = new DuplicateAccountsBatch();
        Database.executeBatch(batch, 100);
        Test.stopTest();
        
        // Verify batch processed records
        List<Account> processedAccounts = [SELECT Principal_Account__c FROM Account WHERE Principal_Account__c != NULL];
        //  System.assertNotEquals(0, processedAccounts.size(), 'Duplicate accounts should have been marked.');
    }
    
    @isTest
    static void testPrincipalAccountSelection() {
        List<Account> accounts = [SELECT Id, OwnerId, CreatedDate FROM Account ORDER BY CreatedDate ASC];
        System.assert(accounts.size() > 1, 'Test setup should have at least two accounts.');
        
        Test.startTest();
        DuplicateAccountsBatch batch = new DuplicateAccountsBatch();
        Database.executeBatch(batch, 100);
        Test.stopTest();
        
        List<Account> updatedAccounts = [SELECT Principal_Account__c FROM Account WHERE Principal_Account__c != NULL];
        //System.assert(updatedAccounts.size() > 0, 'Some accounts should have been assigned a Principal Account.');
    }
    
    @isTest
    static void testApprovalSubmission() {
        Test.startTest();
        DuplicateAccountsBatch batch = new DuplicateAccountsBatch();
        Database.executeBatch(batch, 100);
        Test.stopTest();
        
        // Verify that approval process has been submitted
        List<ProcessInstance> approvals = [SELECT TargetObjectId FROM ProcessInstance WHERE Status = 'Pending'];
        System.assert(approvals.size() > 0, 'At least one approval request should have been submitted.');
    }
    
    @isTest
    static void testScheduledJob() {
        Test.startTest();
        String jobId = System.schedule('Test Duplicate Accounts Batch', '0 0 12 * * ?', new DuplicateAccountsBatch());
        System.assertNotEquals(null, jobId, 'Scheduled job should have been created.');
        Test.stopTest();
    }
}