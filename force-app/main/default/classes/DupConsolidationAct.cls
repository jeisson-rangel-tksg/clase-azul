public with sharing class DupConsolidationAct {
    private static final String STATUS_PENDING = 'Pending';   // Account_Status__c
    private static final String APPROVAL_NAME = 'Duplicate_Accounts';

    public static void stampAndSubmit(List<DupClusterSvc.ClusterDecision> decisions) {
        if (decisions == null || decisions.isEmpty()) {
            return;
        }

        // Load settings once
        DupSettings settings = DupSettings.load();

        // 1) Build updates (one DML): mains + dupes
        List<Account> updates = new List<Account>();
        Set<Id> mainIds = new Set<Id>();

        for (DupClusterSvc.ClusterDecision d : decisions) {
            if (d == null) {
                continue;
            }
            if (d.mainId == null) {
                continue;
            }

            Account mainUpd = new Account();
            mainUpd.Id = d.mainId;
            mainUpd.IsMainAccount__c = true;
            mainUpd.Principal_Account__c = null;
            mainUpd.Account_Status__c = STATUS_PENDING;
            updates.add(mainUpd);
            mainIds.add(d.mainId);

            if (d.others != null) {
                for (Id otherId : d.others) {
                    Account dupUpd = new Account();
                    dupUpd.Id = otherId;
                    dupUpd.IsMainAccount__c = false;
                    dupUpd.Principal_Account__c = d.mainId;
                    updates.add(dupUpd);
                }
            }
        }

        if (!updates.isEmpty()) {
            try {
                update updates;
            } catch (DmlException ex) {
                System.debug(LoggingLevel.ERROR, 'Stamping update failed: ' + ex.getMessage());
            }
        }

        if (mainIds.isEmpty()) {
            return;
        }

        // 2) Re-query mains to get OwnerId + status
        Map<Id, Account> mains = new Map<Id, Account>([
            SELECT Id, OwnerId, Account_Status__c
            FROM Account
            WHERE Id IN :mainIds
        ]);

        // 3) Resolve the "integration fallback" approver user (by Username) once
        Id fallbackApproverId = null;
        if (!String.isBlank(settings.nextApproverUsername)) {
            List<User> us = [
                SELECT Id, Username
                FROM User
                WHERE Username = :settings.nextApproverUsername
                LIMIT 1
            ];
            if (!us.isEmpty()) {
                fallbackApproverId = us[0].Id;
            } else {
                System.debug(LoggingLevel.WARN, 'NextApproverUsername__c not found: ' + settings.nextApproverUsername);
            }
        }

        // 4) Submit mains with conditional next approver
        for (Id mid : mains.keySet()) {
            Account a = mains.get(mid);
            if (a == null) {
                continue;
            }
            if (a.Account_Status__c != STATUS_PENDING) {
                continue;
            }

            Boolean locked = false;
            try {
                locked = Approval.isLocked(a.Id);
            } catch (Exception e) {
                locked = false;
            }
            if (locked) {
                continue;
            }

            // Decide next approver
            Id nextApproverId = null;
            if (!String.isBlank(settings.integrationOwnerId) && a.OwnerId == settings.integrationOwnerId) {
                if (fallbackApproverId != null) {
                    nextApproverId = fallbackApproverId;
                } else {
                    // Fallback if metadata username is missing: owner (even if it's the integration user)
                    nextApproverId = a.OwnerId;
                }
            } else {
                nextApproverId = a.OwnerId;
            }

            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(a.Id);
            req.setProcessDefinitionNameOrId(APPROVAL_NAME);
            req.setComments('Auto-submitted by AcctDupScanBatch');

            // IMPORTANT: the first approval step must be "Let submitter choose the approver manually"
            // for this to take effect.
            List<Id> approvers = new List<Id>();
            approvers.add(nextApproverId);
            req.setNextApproverIds(approvers);

            try {
                Approval.ProcessResult pr = Approval.process(req);
                if (!pr.isSuccess()) {
                    System.debug(LoggingLevel.WARN, 'Approval submit failed for ' + a.Id + ' errors=' + pr.getErrors());
                }
            } catch (Exception e2) {
                System.debug(LoggingLevel.ERROR, 'Approval.process exception for ' + a.Id + ': ' + e2.getMessage());
            }
        }
    }
}
