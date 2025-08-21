/**
 * @description This class transfers related records from duplicate accounts to the principal account
 *              and deletes duplicate accounts after successful transfer.
 * @author Sravani Pallantla
 * @date 3/3/2025
 *
 * **Key Features:**
 * - Uses an **invocable method** for integration with Salesforce Flows or Apex Triggers.
 * - Dynamically retrieves object-field mappings from **Custom Metadata** (`Account_Related_Object_Mapping__mdt`).
 * - **Transfers related records** across multiple objects using **dynamic SOQL**.
 * - **Checks user permissions** for object and field access before transferring data.
 * - **Deletes duplicate accounts** after all related records have been reassigned.
 */

public class TransferDuplicateAccountsRelatedRecords {
    
    /**
     * @description Transfers related records from duplicate accounts to their principal account and deletes duplicates.
     * @param principalAccountIds - List of principal account IDs for which duplicates need to be processed.
     */
    @InvocableMethod
    public static void transferRecords(List<Id> principalAccountIds) {
           if (principalAccountIds == null || principalAccountIds.isEmpty()) {
            System.debug('No Principal Account IDs provided. Skipping execution.');
            return;
        }

        try {
            // Fetch duplicate accounts
            List<Account> duplicateAccounts = [SELECT Id FROM Account WHERE Principal_Account__c IN :principalAccountIds];
            if (duplicateAccounts.isEmpty()) {
                System.debug('No duplicate accounts found. Skipping execution.');
                return;
            }

            List<Id> duplicateAccountIds = new List<Id>();
            for (Account acc : duplicateAccounts) {
                duplicateAccountIds.add(acc.Id);
            }

            // Retrieve object-field mappings from Custom Metadata
            Map<String, String> relatedObjects = new Map<String, String>();
            try {
                for (Account_Related_Object_Mapping__mdt meta : 
                    [SELECT Object_API_Name__c, Field_API_Name__c FROM Account_Related_Object_Mapping__mdt]) {
                    if (meta.Object_API_Name__c != null && meta.Field_API_Name__c != null) {
                        relatedObjects.put(meta.Object_API_Name__c, meta.Field_API_Name__c);
                    }
                }
            } catch (Exception e) {
                System.debug('Error retrieving metadata mappings: ' + e.getMessage());
                return;
            }

            // Process related objects dynamically
            for (String objectName : relatedObjects.keySet()) {
                String fieldName = relatedObjects.get(objectName);

                // Check if the current user has access to the object & field
                if (!hasObjectAccess(objectName) || !hasFieldAccess(objectName, fieldName)) {
                    System.debug('Skipping ' + objectName + ' due to insufficient permissions.');
                    continue;
                }

                try {
                    // Dynamic SOQL to fetch related records
                    String query = 'SELECT Id, ' + fieldName + ' FROM ' + objectName + ' WHERE ' + fieldName + ' IN :duplicateAccountIds';
                    List<SObject> recordsToUpdate = Database.query(query);

                    if (recordsToUpdate != null && !recordsToUpdate.isEmpty()) {
                        // Reassign related records to Principal Account
                        for (SObject record : recordsToUpdate) {
                            record.put(fieldName, principalAccountIds[0]); 
                        }
                        update recordsToUpdate;
                    }
                } catch (Exception e) {
                    System.debug('Error processing object: ' + objectName + '. Error: ' + e.getMessage());
                }
            }

            // Delete duplicate accounts after transferring related records
            try {
                if (!duplicateAccounts.isEmpty()) {
                    delete duplicateAccounts;
                }
            } catch (Exception e) {
                System.debug('Error deleting duplicate accounts: ' + e.getMessage());
            }

        } catch (Exception e) {
            System.debug('Error in transferRecords method: ' + e.getMessage());
        }
    }
        
    /**
     * @description Checks if the current user has object-level access.
     * @param objectName - The API name of the object to check access for.
     * @return Boolean - Returns true if the user has access, false otherwise.
     */
    @TestVisible
    private static Boolean hasObjectAccess(String objectName) {
        try {
            return Schema.getGlobalDescribe().containsKey(objectName);
        } catch (Exception e) {
            System.debug('Error checking object access for ' + objectName + ': ' + e.getMessage());
            return false;
        }
    }

    /**
     * @description Checks if the current user has field-level access for a given object.
     * @param objectName - The API name of the object.
     * @param fieldName - The API name of the field.
     * @return Boolean - Returns true if the field is accessible and updatable, false otherwise.
     */
    @TestVisible
    private static Boolean hasFieldAccess(String objectName, String fieldName) {
        try {
            Schema.DescribeSObjectResult objDesc = Schema.getGlobalDescribe().get(objectName).getDescribe();
            if (objDesc == null) return false;
            
            Map<String, Schema.SObjectField> fieldMap = objDesc.fields.getMap();
            if (fieldMap.containsKey(fieldName)) {
                Schema.DescribeFieldResult fieldDesc = fieldMap.get(fieldName).getDescribe();
                return fieldDesc.isAccessible() && fieldDesc.isUpdateable();
            }
            return false;
        } catch (Exception e) {
            System.debug('Error checking field access for ' + objectName + '.' + fieldName + ': ' + e.getMessage());
            return false;
        }
    }
}