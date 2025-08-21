public without sharing class DepletionsFormController {

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getProductCodeToIdMap(List<String> productCodes) {
        Map<String, String> result = new Map<String, String>();
        if (productCodes == null || productCodes.isEmpty()) return result; // <-- guard
        for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode IN :productCodes]) {
            result.put(p.ProductCode, p.Id);
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getSellerNameToIdMap(List<String> sellerNames) {
        Map<String, String> result = new Map<String, String>();
        if (sellerNames == null || sellerNames.isEmpty()) return result; // <-- guard
        for (Thirdparty_Seller__c s : [SELECT Id, Name FROM Thirdparty_Seller__c WHERE Name IN :sellerNames]) {
            result.put(s.Name, s.Id);
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getTypePicklistValues() {
        List<String> values = new List<String>();
        Schema.DescribeFieldResult fieldResult = Depletion__c.Type__c.getDescribe();
        
        for (Schema.PicklistEntry entry : fieldResult.getPicklistValues()) {
            values.add(entry.getLabel());
        }
        return values;
    }

    @AuraEnabled
    public static Id createThirdPartySeller(String name) {
        if (String.isBlank(name)) {
            throw new AuraHandledException('Seller name is required.');
        }

        Thirdparty_Seller__c newSeller = new Thirdparty_Seller__c(Name = name);
        insert newSeller;
        return newSeller.Id;
    }

    @AuraEnabled(cacheable=true)
    public static String getProductName(String productId){
        return [SELECT Name FROM Product2 WHERE Id = :productId LIMIT 1]?.Name;
    }

    @AuraEnabled(cacheable=true)
    public static String getThirdpartySellerName(String thirdPartySellerId){
        return [SELECT Name FROM Thirdparty_Seller__c WHERE Id = :thirdPartySellerId LIMIT 1]?.Name;
    }

    @AuraEnabled(cacheable=true)
    public static Id validateAccount(String taxId, String email) {
        List<Account> matches = [
            SELECT Id
            FROM Account
            WHERE Tax_Id__c = :taxId AND PersonEmail = :email
            LIMIT 1
        ];
        return matches.isEmpty() ? null : matches[0].Id;
    }

    @AuraEnabled
    public static void createDepletions(List<Map<String, Object>> depletions) {
        System.debug('FUNCIONA?? :' + JSON.serialize(depletions));

        if (depletions == null || depletions.isEmpty()) return;

        List<Depletion__c> recordsToInsert = new List<Depletion__c>();

        for (Map<String, Object> d : depletions) {
            System.debug('ITEM :'+d);
            try {
                Id accountId = (Id) d.get('accountId');
                Id productId = (Id) d.get('productId');
                Id thirdPartySellerId = (Id) d.get('thirdPartySellerId');
                String country = (String) d.get('country');
                String city = (String) d.get('city');
                String state = (String) d.get('state');
                String type = (String) d.get('type');
                Integer quantity = d.get('quantity') != null ? Integer.valueOf(d.get('quantity').toString()) : null;

                if (accountId == null || productId == null || thirdPartySellerId == null) continue;

                recordsToInsert.add(new Depletion__c(
                    Account__c = accountId,
                    Product__c = productId,
                    Thirdparty_Seller__c = thirdPartySellerId,
                    Country__c = country,
                    City__c = city,
                    State__c = state,
                    Type__c = type,
                    Quantity__c = quantity
                ));
            } catch (Exception e) {
                System.debug('Error parsing depletion record: ' + e.getMessage());
            }
        }

        if (!recordsToInsert.isEmpty()) {
            insert recordsToInsert;
        }
    }

}