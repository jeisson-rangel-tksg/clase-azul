/*
 * @description Batch class to detect and consolidate duplicate Accounts in Salesforce.
 * @author Sravani Pallantla
 * @date 28/2/2025
 *
 * **Key Features:**
 * - Detects duplicate accounts using `Datacloud.FindDuplicates`
 * - Identifies a **principal account** based on ownership and creation date
 * - Marks duplicate accounts for consolidation
 * - Submits principal accounts for approval based on owner type
 * - Schedulable to run as a daily batch job
 */
  global class DuplicateAccountsBatch implements Database.Batchable<sObject>,Database.Stateful, Schedulable {
    private static String APPROVAL_NAME='Duplicate_Accounts';
    private static String INTEGRATION_USER='Insights Integration';
    private static String GROUPA_NAME='Non-Integration Account Approvals';
    private static String GROUPB_NAME='Integration Account Approvals';
    private static String COMMENTS='Auto-submitting for duplicate account approval';
    
  global Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator('SELECT Id FROM Account WHERE personemail !=NULL  or phone!=NULL'); 
    }

    global void execute(Database.BatchableContext BC, List<Account> scope) {
       if (scope.isEmpty()) return;
		
        // Use FindDuplicates to get possible duplicate groups
        List<Datacloud.FindDuplicatesResult> duplicateResults = Datacloud.FindDuplicates.findDuplicates(scope);

        // Map to group duplicates based on Duplicate Rule Name
        Map<String, List<Account>> duplicateGroups = new Map<String, List<Account>>();

        for (Datacloud.FindDuplicatesResult result : duplicateResults) {
            List<Datacloud.DuplicateResult> duplicateResultsList = result.getDuplicateResults();

            for (Datacloud.DuplicateResult duplicateResult : duplicateResultsList) {
                
                String duplicateRuleName = duplicateResult.getDuplicateRule(); 

                List<Datacloud.MatchResult> matchResults = duplicateResult.getMatchResults();

                for (Datacloud.MatchResult match : matchResults) {
                    List<Datacloud.MatchRecord> matchRecords = match.getMatchRecords();

                    for (Datacloud.MatchRecord matchRecord : matchRecords) {
                        if (matchRecord.getRecord() instanceof Account) {
                            Account matchedAccount = (Account) matchRecord.getRecord();

                            if (!duplicateGroups.containsKey(duplicateRuleName)) {
                                duplicateGroups.put(duplicateRuleName, new List<Account>());
                            }

                            duplicateGroups.get(duplicateRuleName).add(matchedAccount);
                            
                        }
                        
                    }
                }
            }
        }
		System.debug('duplicateGroups'+ duplicateGroups);
        
        // Process grouped duplicates
        processDuplicateGroups(duplicateGroups);
		
           }

    global void finish(Database.BatchableContext BC) {
        System.debug('Batch job completed.');
    }
    
    global void execute(SchedulableContext SC) {
        Database.executeBatch(new DuplicateAccountsBatch(), 100); // Set batch size as needed
    }
    
    /**
     * @description Processes identified duplicate groups, selecting a principal account and marking duplicates.
     * @param groupedDuplicates - Map of duplicate rule names to lists of duplicate accounts.
     */  
    private void processDuplicateGroups(Map<String, List<Account>> groupedDuplicates) {
        Set<Id> principalAccounts=new Set<id>();
        list<Account> updateduplicateaccounts=new list<Account>();
        
        PrincipalAccountWrapper dupWrap=new PrincipalAccountWrapper(); 
        try{
        
        for (String duplicateRule : groupedDuplicates.keySet()) {
            List<Account> duplicates = groupedDuplicates.get(duplicateRule);
			System.debug('duplicate 60 ' + duplicates);
            if (duplicates.size() > 0) {
                dupWrap = determinePrincipalAccount(duplicates);
                System.debug('71$--'+dupWrap);
				principalAccounts.add(dupWrap.principalAccountId);
                updateduplicateaccounts.addAll(dupWrap.duplicateAccounts);
                System.debug('Principal Account for ' + duplicateRule + ': ' + dupWrap.principalAccountId);
              
            }}
           System.debug('77---$'+updateduplicateaccounts);
           System.debug('78---$'+principalaccounts);
        
            try {
            if(!updateduplicateaccounts.isEmpty())
            	update updateduplicateaccounts;
        	 } catch (DmlException dmlEx) {
                System.debug('Error updating duplicate accounts: ' + dmlEx.getMessage());
            }
        	if (!principalAccounts.isEmpty()) {
            try {
                initiateApprovalProcess(principalAccounts);
            } catch (Exception e) {
                System.debug('Error initiating approval process: ' + e.getMessage());
            }
        }
           } catch (Exception e) {
        System.debug('Unexpected error in processDuplicateGroups: ' + e.getMessage());
        throw new CustomException('An error occurred while processing duplicate groups: ' + e.getMessage());
    }
    }
    
    /**
     * @description Determines the principal account from a list of duplicate accounts.
     * @param duplicates - List of duplicate accounts.
     * @return PrincipalAccountWrapper - Wrapper containing the principal account ID and updated duplicate accounts.
     */
    private PrincipalAccountWrapper determinePrincipalAccount(List<Account> duplicates) {
                
        Account principal = null;
        List<Account> acclistsupdated= new List<Account>();
        PrincipalAccountWrapper Dupwrapper=new PrincipalAccountWrapper();
        List<Account> accduplistsupdated=new List<Account>();
        
        try{
             Id integrationUserId = getIntegrationUserId();
        if (integrationUserId == null) {
            throw new CustomException('Integration User ID not found. Process cannot continue.');
             }       
        acclistsupdated=getAcccountInfo(duplicates);
            
        if (acclistsupdated.isEmpty()) {
        throw new CustomException('No accounts found in duplicates list.');
        	}
        
        for (Account acc : acclistsupdated) {
            
            System.debug('95--$'+acc.OwnerId);
            System.debug('96---$'+integrationUserId);
            if (acc.OwnerId != integrationUserId) {
                principal = acc;
                System.debug('99--$'+principal.id);
                break;
            }
        }

        if (principal == null) {
            principal = acclistsupdated[0]; // Default to the first if all have the same owner
            for (Account acc : acclistsupdated) {
                System.debug('107--$'+acc.CreatedDate);
           		if (acc.CreatedDate < principal.CreatedDate) {
                    principal = acc;
                    System.debug('109--$'+principal.id);
                }
            }
        }
        for (Account acc : acclistsupdated) {
        if(acc.Id != principal.Id)
           accduplistsupdated.add(new Account(Id = acc.Id, Principal_Account__c = principal.Id));
        }
        
        Dupwrapper.principalAccountId=principal.Id;
        Dupwrapper.duplicateAccounts=accduplistsupdated;
        } 
        catch (Exception e) {
        System.debug('Error in determinePrincipalAccount: ' + e.getMessage());
        throw new CustomException('An error occurred while determining the principal account: ' + e.getMessage());
        }

        return Dupwrapper;
        
    }
      
    /**
     * @description Submits principal accounts for approval.
     * @param principalAccountslist - Set of principal account IDs.
     */
    private void initiateApprovalProcess(Set<Id> principalAccountslist) {
        if (principalAccountslist == null || principalAccountslist.isEmpty()) {
        System.debug('No principal accounts to process for approval.');
        return;
    	}
        try{
        Id integrationUserId = getIntegrationUserId();
        Id GroupAId = getGroupIdByName(GROUPA_NAME);
        Id GroupBId = getGroupIdByName(GROUPB_NAME);
        
         if (integrationUserId == null || GroupAId == null || GroupBId == null) {
            System.debug('Error: One or more required IDs (Integration User, GroupA, GroupB) are null.');
            throw new CustomException('Required approval IDs are missing.');
        }
        list<Account> principalAccounts = [SELECT Id, OwnerId FROM Account WHERE Id in :principalAccountslist];
		if (principalAccounts.isEmpty()) {
            System.debug('No accounts found for approval.');
            return;
        }
            
        List<Approval.ProcessSubmitRequest> approvalRequests = new List<Approval.ProcessSubmitRequest>();
        
        
		for (Account acc : principalAccounts) {
            try{
            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(acc.Id);
            req.setComments(COMMENTS);
            req.setSubmitterId(UserInfo.getUserId());
            req.setProcessDefinitionNameOrId(APPROVAL_NAME);
            // 🔹 Route Approval Based on Owner
            
            if (acc.OwnerId != integrationUserId) {
                req.setNextApproverIds(new List<Id>{GroupAId}); // Queue A (Non-Integration)
            } else {
                req.setNextApproverIds(new List<Id>{GroupBId}); // Queue B (Integration)
            }

            approvalRequests.add(req);
        }catch (Exception e) {
                System.debug('Error processing approval request for Account ID ' + acc.Id + ': ' + e.getMessage());
                continue; // Skip this account and process the next
            }
        }

        if (!approvalRequests.isEmpty()) {
             try {
                Approval.process(approvalRequests);
                System.debug('Approval requests submitted: ' + approvalRequests.size());
            } catch (Exception e) {
                System.debug('Error submitting approval requests: ' + e.getMessage());
                throw new CustomException('Failed to submit approval requests: ' + e.getMessage());
            }
        }
    } catch (Exception e) {
        System.debug('Unexpected error in initiateApprovalProcess: ' + e.getMessage());
        throw new CustomException('An error occurred while initiating the approval process: ' + e.getMessage());
    }
    }
            
    // Fetch Public Group ID by Name
	private static Id getGroupIdByName(String groupName) {
    Group grp = [SELECT Id FROM Group WHERE Name = :groupName AND Type = 'Regular' LIMIT 1];
    return grp != null ? grp.Id : null;
	}
    
    private static Id getIntegrationUserId() {
        User integrationUser = [SELECT Id FROM User WHERE name =: INTEGRATION_USER LIMIT 1];
        return integrationUser != null ? integrationUser.Id : null;
    }
    
    private static List<Account> getAcccountInfo(List<Account> accounts) {
        List<Id> duplicateAccountsIds=new List<Id>();
        
        for (Account acc : accounts) {
            duplicateAccountsIds.add(acc.Id);
        }
        List<Account> acclist=[select id,OwnerId,createddate from account where id in : duplicateAccountsIds order by createddate asc];
        System.debug('ALL FOUND ACCOUNTS: '+acclist);
        return acclist; 
    }
    private class PrincipalAccountWrapper{
        Id principalAccountId;
        List<Account> duplicateAccounts;
      
    }
    public class CustomException extends Exception {}
}