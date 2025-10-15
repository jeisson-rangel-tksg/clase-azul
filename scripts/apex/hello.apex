// Use .apex files to store anonymous Apex.
// You can execute anonymous Apex in VS Code by selecting the
//     apex text and running the command:
//     SFDX: Execute Anonymous Apex with Currently Selected Text
// You can also execute the entire file by running the command:
//     SFDX: Execute Anonymous Apex with Editor Contents

// Example: insert two accounts that would normally be considered duplicates
Database.DMLOptions dmlOpts = new Database.DMLOptions();
dmlOpts.duplicateRuleHeader.allowSave = true;            // allow saving even if duplicate rules match
//dmlOpts.duplicateRuleHeader.includeRecordDetails = true; // optional: include extra details in results
dmlOpts.duplicateRuleHeader.runAsCurrentUser = true;     // run duplicate rule checks as current user (true/false as needed)

Account pa = new Account(
            FirstName = 'Jeisson', LastName = 'Rangel', PersonEmail = 'jeisson.rangel@theksquaregroup.com',
            AccountSource = CLA_FormConstants.DEFAULT_ACCOUNT_SOURCE,
            CLA_Fuente__c = CLA_FormConstants.DEFAULT_SOURCE,
            CLA_SubCategory__c = CLA_FormConstants.DEFAULT_SUBCATEGORY,
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get(CLA_FormConstants.RECORD_TYPE_PERSON_ACCOUNT).getRecordTypeId());

Account pa1 = new Account(
            FirstName = 'Jeisson', LastName = 'Rangel', PersonEmail = 'jeisson.rangel1@theksquaregroup.com',
            AccountSource = CLA_FormConstants.DEFAULT_ACCOUNT_SOURCE,
            CLA_Fuente__c = CLA_FormConstants.DEFAULT_SOURCE,
            CLA_SubCategory__c = CLA_FormConstants.DEFAULT_SUBCATEGORY,
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get(CLA_FormConstants.RECORD_TYPE_PERSON_ACCOUNT).getRecordTypeId());

Account pa2 = new Account(
            FirstName = 'Jeisson', LastName = 'Rangel', PersonEmail = 'jeisson.rangel2@theksquaregroup.com',
            AccountSource = CLA_FormConstants.DEFAULT_ACCOUNT_SOURCE,
            CLA_Fuente__c = CLA_FormConstants.DEFAULT_SOURCE,
            CLA_SubCategory__c = CLA_FormConstants.DEFAULT_SUBCATEGORY,
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get(CLA_FormConstants.RECORD_TYPE_PERSON_ACCOUNT).getRecordTypeId());

Account pa3 = new Account(
            FirstName = 'Jeisson', LastName = 'Rangel', PersonEmail = 'jeisson.rangel3@theksquaregroup.com',
            AccountSource = CLA_FormConstants.DEFAULT_ACCOUNT_SOURCE,
            CLA_Fuente__c = CLA_FormConstants.DEFAULT_SOURCE,
            CLA_SubCategory__c = CLA_FormConstants.DEFAULT_SUBCATEGORY,
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get(CLA_FormConstants.RECORD_TYPE_PERSON_ACCOUNT).getRecordTypeId());

List<Account> toInsert = new List<Account>{ pa1, pa2, pa3 };

// Use Database.insert overload that accepts DMLOptions
Database.SaveResult[] results = Database.insert(toInsert, dmlOpts);

// Inspect results
for (Integer i = 0; i < results.size(); i++) {
    if (results[i].isSuccess()) {
        System.debug('Inserted Account id: ' + results[i].getId());
    } else {
        // If something else failed, log the errors
        for (Database.Error err : results[i].getErrors()) {
            System.debug('Error inserting record index ' + i + ': ' + err.getStatusCode() + ' - ' + err.getMessage());
        }
    }
}
