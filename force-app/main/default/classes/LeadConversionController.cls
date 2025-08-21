@RestResource(urlMapping='/convertLeadByEmail')
global with sharing class LeadConversionController {

    @HttpPost
    global static LeadConversionResponse convertLeadByEmail() {
        RestRequest req = RestContext.request;
        String email = req.params.get('email');
        Boolean isOpportunity = paramIsPresent(req.params, 'isOpportunity');

        if (String.isBlank(email)) {
            return new LeadConversionResponse('Missing required query parameter: email', null, 400);
        }

        if (!Schema.sObjectType.Lead.isAccessible() || !Schema.sObjectType.Lead.fields.Email.isAccessible()) {
            return new LeadConversionResponse('User does not have access to Lead object or Email field.', null, 403);
        }

        if (!Schema.sObjectType.Account.isCreateable()) {
            return new LeadConversionResponse('User does not have permission to create Accounts.', null, 403);
        }

        if (isOpportunity && !Schema.sObjectType.Opportunity.isCreateable()) {
            return new LeadConversionResponse('User does not have permission to create Opportunities.', null, 403);
        }

        List<Lead> leads = [
            SELECT Id, IsConverted, LastModifiedDate
            FROM Lead
            WHERE Email = :email
            ORDER BY LastModifiedDate DESC
        ];

        if (leads.isEmpty()) {
            return new LeadConversionResponse('No leads found with email: ' + email, null, 404);
        }

        Lead targetLead = leads[0];

        if (targetLead.IsConverted) {
            return new LeadConversionResponse('Lead with email ' + email + ' is already converted.', null, 200);
        }

        try {
            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(targetLead.Id);
            lc.setDoNotCreateOpportunity(!isOpportunity);
            lc.setConvertedStatus(getDefaultConvertedStatus());

            Database.LeadConvertResult result = Database.convertLead(lc);

            if (result.isSuccess()) {
                Account createdAccount = [SELECT isPersonAccount FROM Account WHERE Id = :result.getAccountId() limit 1];
                if(createdAccount.isPersonAccount){
                    createdAccount = LeadConversionUtils.updateAccountInfoFromLead(targetLead.Id, result.getAccountId());
                    update createdAccount;
                }
                return new LeadConversionResponse('Lead converted successfully.', result.getAccountId(), 200);
            } else {
                String msg = (result.getErrors().isEmpty())
                    ? 'Unknown conversion error.'
                    : result.getErrors()[0].getMessage();
                return new LeadConversionResponse('Lead conversion failed: ' + msg, null, 500);
            }

        } catch (Exception e) {
            return new LeadConversionResponse('Error during conversion: ' + e.getMessage(), null, 500);
        }
    }

    @TestVisible
    private static String getDefaultConvertedStatus() {
        if (!Schema.sObjectType.LeadStatus.isAccessible()) {
            throw new QueryException('User does not have permission to access Lead Status SObject.');
        }
        List<LeadStatus> statuses = [
            SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1
        ];
        if (statuses.isEmpty()) {
            throw new QueryException('No valid converted LeadStatus found in the org.');
        }
        return statuses[0].MasterLabel;
    }

    private static Boolean paramIsPresent(Map<String, String> params, String key) {
        return params != null && params.containsKey(key);
    }

    global class LeadConversionResponse {
        public String message;
        public String accountId;
        private Integer statusCode;

        public LeadConversionResponse(String message, String accountId, Integer statusCode) {
            this.message = message;
            this.accountId = accountId;
            this.statusCode = statusCode;

            RestContext.response.statusCode = statusCode;
            RestContext.response.addHeader('Content-Type', 'application/json');
            RestContext.response.responseBody = Blob.valueOf(JSON.serialize(this));
        }
    }
}