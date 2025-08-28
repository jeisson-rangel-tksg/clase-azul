public without sharing class CLA_FormVPMPController {

    @AuraEnabled(cacheable=true)
    public static Boolean isCampaignActive(Id campaignId) {
        if (String.isBlank(campaignId)) {
            return false;
        }
        List<Campaign> camps = [
            SELECT IsActive
            FROM Campaign
            WHERE Id = :campaignId
            LIMIT 1
        ];
        if (camps.isEmpty()) {
            return false;
        }
        return camps[0].IsActive;
    }

    @AuraEnabled(cacheable=true)
    public static List<Product2> getCampaignProducts(String campaignId) {
        return [
            SELECT Id, Name, Description, Family
            FROM Product2
            WHERE Id IN (
                SELECT Product__c FROM CampaignProduct__c WHERE Campaign__c = :campaignId
            )
            WITH SYSTEM_MODE
        ];
    }

    /**
     * Retrieves values from the Location__c field of campaign.
     *
     * @param campaignId - Campaign Id.
     * @return Map containing locations available for the campaign.
     * @throws AuraHandledException if campaign id is null or the user has no access to the field Location__c.
     */
    @AuraEnabled(cacheable=true)
    public static List<CLA_FormVPMPController.PickupLocationOption> getPickupLocationsFromCampaign(Id campaignId) {

        List<CLA_FormVPMPController.PickupLocationOption> options = new List<CLA_FormVPMPController.PickupLocationOption>();
        Map<String, String> apiToLabel = new Map<String, String>();

        if (String.isBlank(campaignId)) {
            throw new AuraHandledException('Missing Campaign Id.');
        }

        if (!Schema.sObjectType.Campaign.fields.Location__c.isAccessible()) {
            throw new AuraHandledException('Unable to access this field.');
        }

        Campaign camp = [
            SELECT Location__c
            FROM Campaign
            WHERE Id = :campaignId
            LIMIT 1
        ];

        Schema.DescribeFieldResult describe = Campaign.Location__c.getDescribe();
        for (Schema.PicklistEntry entry : describe.getPicklistValues()) {
                apiToLabel.put(entry.getValue(), entry.getLabel());
        }

        String selected = String.isBlank(camp.Location__c) ? CLA_FormConstants.DEFAULT_PICKUP_LOCATION_OPTIONS : camp.Location__c;

        List<String> selectedValues = selected.split(';');

        for (String apiValue : selectedValues) {
            String label = apiToLabel.get(apiValue);
            options.add(new CLA_FormVPMPController.PickupLocationOption(apiValue, label));
        }

        return options;
    }

    @AuraEnabled(cacheable=true)
    public static PickupResponse getPickupLocationsAndProductsByCampaign(Id campaignId) {

        List<PickupLocationOption> pickupOptions = new List<PickupLocationOption>();
        Map<String, List<Product2>> productsByLocation = new Map<String, List<Product2>>();
        System.debug('getPickupLocationsAndProductsByCampaign | campaignId: '+campaignId);

        if (String.isBlank(campaignId)) {
            throw new AuraHandledException('Missing Campaign Id.');
        }

        try {

            // 1. Query all campaign-linked almacenes
            List<Almacen_de_campa_a__c> almacenLinks = [
                SELECT Id, Name, Almacen__r.Id, Almacen__r.Name
                FROM Almacen_de_campa_a__c
                WHERE Campaign__c = :campaignId
            ];

            if (almacenLinks.isEmpty()) {
                return new PickupResponse(pickupOptions, productsByLocation);
            }

            Map<Id, Almacen_de_campa_a__c> almacenLinkByAlmacenId = new Map<Id, Almacen_de_campa_a__c>();
            Set<Id> almacenIds = new Set<Id>();

            for (Almacen_de_campa_a__c link : almacenLinks) {
                if (link.Almacen__r != null) {
                    almacenIds.add(link.Almacen__r.Id);
                    almacenLinkByAlmacenId.put(link.Almacen__r.Id, link);
                }
            }

            // 2. Query Inventario__c records with quantity > 0
            List<Inventario__c> inventarios = [
                SELECT Product__r.Id, Product__r.Name, Product__r.Description, Product__r.Family,
                    Almacen__r.Id, Almacen__r.Name,
                    Quantity__c
                FROM Inventario__c
                WHERE Almacen__r.Id IN :almacenIds
                AND Quantity__c > 0
            ];

            // 3. Group products by almacen name
            Map<String, List<Product2>> tempProductMap = new Map<String, List<Product2>>();
            Set<Id> validAlmacenIds = new Set<Id>();

            for (Inventario__c inv : inventarios) {
                Id almacenId = inv.Almacen__r?.Id;
                String almacenName = inv.Almacen__r?.Name;

                if (almacenId == null || almacenName == null || inv.Product__r == null) continue;

                if (!tempProductMap.containsKey(almacenName)) {
                    tempProductMap.put(almacenName, new List<Product2>());
                }
                tempProductMap.get(almacenName).add(inv.Product__r);
                validAlmacenIds.add(almacenId); // track only almacenes with at least 1 product with quantity > 0
            }

            // 4. Build valid pickup options
            for (Id almacenId : validAlmacenIds) {
                Almacen_de_campa_a__c link = almacenLinkByAlmacenId.get(almacenId);
                if (link != null && link.Almacen__r?.Name != null && link.Name != null) {
                    pickupOptions.add(new PickupLocationOption(
                        link.Almacen__r.Name,  // value
                        link.Name              // label
                    ));

                    productsByLocation.put(link.Almacen__r.Name, tempProductMap.get(link.Almacen__r.Name));
                }
            }
        } catch (Exception e) {
            System.debug(e);
        }
        return new PickupResponse(pickupOptions, productsByLocation);
    }

    @AuraEnabled(cacheable=true)
    public static Boolean canUserCreateOrder(Id campaignId, String email) {

        if (String.isBlank(campaignId) || String.isBlank(email)) return true;

        if (isEventOrLaunch(campaignId)) {
            return true;
        }

        Set<Id> scopeCampaignIds = collectParentAndImmediateChildren(campaignId);

        Account pa = [
            SELECT Id, PersonContactId
            FROM Account
            WHERE IsPersonAccount = true AND PersonEmail = :email
            LIMIT 1
        ];
        if (pa == null) return true;
        if (pa.PersonContactId == null) return true;
       
        Integer cmCount = [
            SELECT COUNT()
            FROM CampaignMember
            WHERE CampaignId IN :scopeCampaignIds
            AND ContactId = :pa.PersonContactId
        ];
        if (cmCount == 0) return false;

        Boolean hasOrder = [
            SELECT COUNT()
            FROM Order
            WHERE AccountId = :pa.Id
            AND Campaign__c IN :scopeCampaignIds
            LIMIT 1
        ] > 0;

        return !hasOrder;
    }

    private static Boolean isEventOrLaunch(Id campaignId) {
        return [
            SELECT COUNT()
            FROM Campaign
            WHERE Id = :campaignId
            AND (Type = 'Event' OR Type = 'Launch')
            LIMIT 1
        ] > 0;
    }

    /** Get Campaign and Child Campaigns */
    private static Set<Id> collectParentAndImmediateChildren(Id parentId) {
        Set<Id> ids = new Set<Id>{ parentId };
        for (Campaign c : [SELECT Id FROM Campaign WHERE ParentId = :parentId LIMIT 5000]) {
            ids.add(c.Id);
        }
        return ids;
    }

    /**
     * Retrieves Person Account by email. If not found, creates one using the email as name.
     *
     * @param email - Email address tied to the Person Account.
     * @return Map containing accountId and optInAnnualNewsletter preference.
     * @throws AuraHandledException if email is invalid.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getPersonAccountByEmail(String email) {
        if (String.isBlank(email)) {
            throw new AuraHandledException('Invalid email.');
        }

        List<Account> personAccounts = CLA_FormUtils.getPersonAccountByEmail(email);

        if (personAccounts.isEmpty()) {
            return new Map<String, Object>{
                'accountId' => null,
                'optInAnnualNewsletter' => false
            };
        } else {
            Account acc = personAccounts[0];
            return new Map<String, Object>{
                'accountId' => acc.Id,
                'optInAnnualNewsletter' => acc.CLA_OptInAnnualNewsletter__pc,
                'birthdate' => acc.PersonBirthdate,
                'region' => acc.Region__pc,
                'country' => acc.Country__pc,
                'state' => acc.State__pc
            };
        }
    }

    @AuraEnabled
    public static void updateMissingAccountFields(Map<String, Object> input) {
        Id accountId = (Id) input.get('accountId');
        if (accountId == null) {
            throw new AuraHandledException('Missing account ID.');
        }

        Account accToUpdate = new Account(Id = accountId);

        if (input.containsKey('birthdate')) {
            accToUpdate.PersonBirthdate = Date.valueOf((String) input.get('birthdate'));
        }

        if (input.containsKey('region')) {
            accToUpdate.Region__pc = (String) input.get('region');
        }

        if (input.containsKey('country')) {
            accToUpdate.Country__pc = (String) input.get('country');
        }

        if (input.containsKey('state')) {
            accToUpdate.State__pc = (String) input.get('state');
        }

        update accToUpdate;
    }


    @AuraEnabled
    public static void createOrders(Map<String, Object> input) {
        CLA_FormUtils.createOrderWithItems(input);
    }

    @AuraEnabled(cacheable=true)
    public static List<WishlistOption> getCampaignWishlists(Id campaignId) {
        if (String.isBlank(campaignId)) {
            return new List<WishlistOption>();
        }

        List<WishlistOption> result = new List<WishlistOption>();
        for (Campaign_Wishlist__c wl : [
            SELECT Id, Label_EN__c, Label_ES__c, Main_Interest__c, Sub_Interest__c
            FROM Campaign_Wishlist__c
            WHERE Campaign__c = :campaignId
            ORDER BY CreatedDate ASC
        ]) {
            result.add(new WishlistOption(
                wl.Id,
                wl.Label_EN__c,
                wl.Label_ES__c,
                wl.Main_Interest__c,
                wl.Sub_Interest__c
            ));
        }
        return result;
    }

    public class WishlistOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String labelEn;
        @AuraEnabled public String labelEs;
        @AuraEnabled public String mainInterest;
        @AuraEnabled public String subInterest;

        public WishlistOption(Id id, String en, String es, String mainI, String subI) {
            this.id = id; this.labelEn = en; this.labelEs = es;
            this.mainInterest = mainI; this.subInterest = subI;
        }
    }

    /**
     * Wrapper class to represent the values and labels for the selected items
     * in the multi-selection picklist Location.
     */
    public class PickupLocationOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;

        public PickupLocationOption(String value, String label) {
            this.value = value;
            this.label = label;
        }
    }

    public class PickupResponse {
        @AuraEnabled public List<PickupLocationOption> pickupLocations;
        @AuraEnabled public Map<String, List<Product2>> productsByLocation;

        public PickupResponse(List<PickupLocationOption> locations, Map<String, List<Product2>> products) {
            this.pickupLocations = locations;
            this.productsByLocation = products;
        }
    }
    
}