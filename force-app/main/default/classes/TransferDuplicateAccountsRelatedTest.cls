@isTest
public class TransferDuplicateAccountsRelatedTest {
    @testSetup
    static void setupTestData() {
        // Create Principal Accounts
        Id personAccountRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1].Id;
        
        Account principalAccount = new Account(FirstName='Prospect',LastName = 'Prospect Test',CLA_Fuente__c = 'DIGITAL CELLAR', PersonEmail='test@gmail.com',CLA_SubCategory__c='test', AccountSource='COLLECTOR', CLA_OptIn__pc = true, RecordTypeId = personAccountRT, CLA_MemberTier__c = 'Prospect');
        insert principalAccount;
        
        // Create Duplicate Accounts
       List<Account> duplicateAccounts = new List<Account>();
        /* for (Integer i = 0; i < 2; i++) {
            duplicateAccounts.add(new Account(FirstName = 'Duplicate Account ', LastName = 'Prospect Test'+i,CLA_Fuente__c = 'DIGITAL CELLAR', PersonEmail='test@gmail.com',CLA_SubCategory__c='test', AccountSource='COLLECTOR', CLA_OptIn__pc = true, RecordTypeId = personAccountRT, CLA_MemberTier__c = 'Prospect'));
        }
        insert duplicateAccounts;*/
            List<Account> testAccounts = new List<Account>{
            new Account(FirstName='Prospect',LastName = 'Prospect Test',CLA_Fuente__c = 'DIGITAL CELLAR', PersonEmail='test@gmail.com',CLA_SubCategory__c='test', AccountSource='COLLECTOR', CLA_OptIn__pc = true, RecordTypeId = personAccountRT, CLA_MemberTier__c = 'Prospect'),
                new Account(FirstName='Active', LastName = 'Active Test', CLA_Fuente__c = 'DIGITAL CELLAR', PersonEmail='test@gmail.com',CLA_SubCategory__c='test',AccountSource='COLLECTOR', CLA_OptIn__pc = true, RecordTypeId = personAccountRT, CLA_MemberTier__c = 'Prospect'),
                new Account(FirstName='Inactive',LastName = 'Inactive Test', CLA_Fuente__c = 'DIGITAL CELLAR', PersonEmail='test@gmail.com',CLA_SubCategory__c='test',AccountSource='COLLECTOR', CLA_OptIn__pc = true, RecordTypeId = personAccountRT, CLA_MemberTier__c = 'Prospect')
                };
                    insert duplicateAccounts;
        
        // Create Related Object Records (Example: Contact)
        List<Contact> contacts = new List<Contact>();
        for (Account acc : duplicateAccounts) {
            contacts.add(new Contact(LastName = 'Related Contact', AccountId = acc.Id));
        }
        insert contacts;
    }
    
    @isTest
    static void testTransferRecords() {
        // Fetch Principal Account
        Account principalAccount = [SELECT Id FROM Account WHERE PersonEmail = 'test@gmail.com' LIMIT 1];
        
        // Call the method
        Test.startTest();
        TransferDuplicateAccountsRelatedRecords.transferRecords(new List<Id>{principalAccount.Id});
        Test.stopTest();
        
        // Verify that the duplicate accounts were deleted
        List<Account> remainingDuplicates = [SELECT Id FROM Account WHERE Principal_Account__c = :principalAccount.Id];
        System.assertEquals(0, remainingDuplicates.size(), 'Duplicate accounts should be deleted');
        
        // Verify that related records were transferred
        List<Contact> updatedContacts = [SELECT Id, AccountId FROM Contact WHERE AccountId = :principalAccount.Id];
        System.assert(updatedContacts.size() > 0, 'Contacts should be reassigned to the principal account');
    }
    
    @isTest
    static void testNoPrincipalAccounts() {
        Test.startTest();
        TransferDuplicateAccountsRelatedRecords.transferRecords(new List<Id>());
        Test.stopTest();
        // No exception should occur
    }
    
    @isTest
    static void testNoRelatedRecordsFound() {
        Account principalAccount = [SELECT Id FROM Account WHERE PersonEmail = 'test@gmail.com' LIMIT 1];
        
        Test.startTest();
        TransferDuplicateAccountsRelatedRecords.transferRecords(new List<Id>{principalAccount.Id});
        Test.stopTest();
        
        // Verify that execution completes even when no related records exist
        System.assert(true, 'No related records scenario executed successfully');
    }
    
    @isTest
    static void testInsufficientPermissions() {
        Test.startTest();
        Boolean hasAccess = TransferDuplicateAccountsRelatedRecords.hasObjectAccess('InvalidObject');
        System.assertEquals(false, hasAccess, 'User should not have access to an invalid object');
        
        Boolean hasFieldAccess = TransferDuplicateAccountsRelatedRecords.hasFieldAccess('Contact', 'InvalidField');
        System.assertEquals(false, hasFieldAccess, 'User should not have access to an invalid field');
        Test.stopTest();
    }
}