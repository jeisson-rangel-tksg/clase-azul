/**
 * @description 
 * Utility class for handling form-based creation of Person Accounts, Orders, and Order Items.
 * 
 * @author 
 * Luis Vargas, Company: The KSquare Group
 * @date 
 * May 31, 2025
 * 
 * @note 
 * This class is designed to work in environments where strict FLS and CRUD compliance is required.
 */
public without sharing class CLA_FormUtils {

    /**
     * Retrieves a list of Person Accounts by email.
     * 
     * @param email The email to search for.
     * @return List of matching Person Accounts or an empty list if none are found.
     * @throws AuraHandledException if the running user lacks access to the PersonEmail field.
     */
    @AuraEnabled
    public static List<Account> getPersonAccountByEmail(String email) {
        if (String.isBlank(email)) {
            return new List<Account>();
        }

        if (!Schema.sObjectType.Account.fields.PersonEmail.isAccessible()) {
            throw new AuraHandledException('Access to email field is not permitted.');
        }

        return [
            SELECT Id,
                CLA_OptInAnnualNewsletter__pc,
                PersonBirthdate,
                Region__pc,
                Country__pc,
                State__pc
            FROM Account 
            WHERE PersonEmail = :email AND IsPersonAccount = true 
            LIMIT 1
        ];
    }

    /**
     * Retrieves the ID of the Standard Pricebook2.
     * 
     * @return The Standard Pricebook2 Id.
     * @throws AuraHandledException if the standard pricebook is not found or access is denied.
     */
    public static Id getStandardPricebookId() {
        if (!Schema.sObjectType.Pricebook2.fields.IsStandard.isAccessible()) {
            throw new AuraHandledException('Access to isStandard field is not permitted.');
        }
        List<Pricebook2> pricebooks = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
        if (pricebooks.isEmpty()) {
            throw new AuraHandledException(CLA_FormConstants.ERR_STANDARD_PRICEBOOK_NOT_FOUND);
        }
        return pricebooks[0].Id;
    }

    /**
     * Builds a map linking Product2 Ids to their corresponding PricebookEntry details.
     * 
     * @param productIds Set of Product2 Ids.
     * @return Map of Product2Id to a map containing entryId and unitPrice.
     * @throws AuraHandledException if access to any required PricebookEntry fields is denied.
     */
    public static Map<Id, Map<String, Object>> getPricebookEntryMap(Set<Id> productIds) {

        Id standardPricebookId = getStandardPricebookId();
        Map<Id, Map<String, Object>> result = new Map<Id, Map<String, Object>>();
        if (!(Schema.sObjectType.PricebookEntry.fields.UnitPrice.isAccessible() &&
            Schema.sObjectType.PricebookEntry.fields.Product2Id.isAccessible() &&
            Schema.sObjectType.PricebookEntry.fields.Pricebook2Id.isAccessible() &&
            Schema.sObjectType.PricebookEntry.fields.IsActive.isAccessible())) {
            throw new AuraHandledException('Access to PricebookEntry fields is not permitted.');
        }
        for (PricebookEntry pbe : [
            SELECT Id, UnitPrice, Product2Id
            FROM PricebookEntry
            WHERE Pricebook2Id = :standardPricebookId
            AND Product2Id IN :productIds
            AND IsActive = true
        ]) {
            result.put(pbe.Product2Id, new Map<String, Object>{
                'entryId' => pbe.Id,
                'unitPrice' => pbe.UnitPrice
            });
        }
        return result;
    }

    /**
     * Retrieves an existing Person Account by email or creates a new one.
     * 
     * @param input The PersonAccountInput data.
     * @return The existing or newly created Person Account.
     * @throws AuraHandledException if required fields are missing or if FLS prevents field updates.
     */
    public static Account getOrCreatePersonAccount(PersonAccountInput input) {
        if (String.isBlank(input.email)) {
            throw new AuraHandledException('Email is required.');
        }
        if (!Schema.sObjectType.Account.isCreateable()) {
            AuraHandledException e = new AuraHandledException(CLA_FormConstants.ERR_ACCOUNT_CREATE);
            e.setMessage(CLA_FormConstants.ERR_ACCOUNT_CREATE);
            throw e;
        }
        
        List<Account> existing = getPersonAccountByEmail(input.email);
        Account account;
        
        if (existing.isEmpty()) {
            account = new Account(
                FirstName = String.isBlank(input.firstName) ? input.email : input.firstName,
                LastName = String.isBlank(input.lastName) ? input.email : input.lastName,
                PersonEmail = input.email,
                Phone = input.phone,
                PersonBirthdate = input.birthdate,
                Region__pc = input.region,
                Country__pc = input.country,
                State__pc = input.state,
                CLA_OptIn__pc = true,
                AccountSource = CLA_FormConstants.DEFAULT_ACCOUNT_SOURCE,
                CLA_Fuente__c = input.source.toUpperCase(),
                CLA_SubCategory__c = input.subcategory,
                PersonMailingStreet     = input.mailingStreet,
                PersonMailingCity       = input.mailingCity,
                PersonMailingPostalCode = input.mailingPostalCode,
                RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                    .get(CLA_FormConstants.RECORD_TYPE_PERSON_ACCOUNT).getRecordTypeId()
            );
            insert account;
        } else {
            account = existing[0];
            CLA_FormUtils.WaitingListInput waitingListInput = new CLA_FormUtils.WaitingListInput();
            waitingListInput.accountId = account.Id;
            waitingListInput.accountSource = CLA_FormConstants.DEFAULT_ACCOUNT_SOURCE;
            waitingListInput.sourceCategory = input.source.toUpperCase();
            waitingListInput.sourceSubCategory = input.subcategory;

            createWaitingListRecord(waitingListInput);
        }

        if (input.optInNewsletter != null && Schema.sObjectType.Account.fields.CLA_OptInAnnualNewsletter__pc.isUpdateable()) {
            account.CLA_OptInAnnualNewsletter__pc = input.optInNewsletter;
            account.PersonHasOptedOutOfEmail = !input.optInNewsletter;
            update account;
        }

        return account;
    }

    /**
     * Creates an Order for a given Person Account.
     * 
     * @param account The Person Account for which the order is created.
     * @param input Additional input parameters for the Order.
     * @return The newly created Order record.
     * @throws AuraHandledException if the user does not have create access to the Order object.
     */
    private static Order createOrder(Account account, Map<String, Object> input) {
        if (!Schema.sObjectType.Order.isCreateable()) {
            throw new AuraHandledException(CLA_FormConstants.ERR_ORDER_CREATE);
        }

        System.debug('RETAILER: '+input.get('retailerId'));

        Order order = new Order(
            AccountId = account.Id,
            EffectiveDate = Date.today(),
            Status = CLA_FormConstants.DEFAULT_ORDER_STATUS,
            Type = CLA_FormConstants.DEFAULT_ORDER_TYPE,
            RecordTypeId = Schema.SObjectType.Order.getRecordTypeInfosByDeveloperName()
                .get(CLA_FormConstants.RECORD_TYPE_ORDER_ALLOCATION).getRecordTypeId(),
            Pricebook2Id = getStandardPricebookId(),
            Campaign__c = (String) input.get('campaignId'),
            CLA_Location__c = (String) input.get('pickupLocation'),
            Distributor_Retailer__c = (String) input.get('retailerId')
        );
        System.debug('ORDER RET: '+order.Distributor_Retailer__c);
        insert order;
        return order;
    }

    /**
     * Prepares a list of OrderItems based on the provided products and pricing information.
     * 
     * @param order The associated Order.
     * @param productEntries List of product entries containing productId and quantity.
     * @param pricebookEntryMap Pricing information map.
     * @return List of OrderItem records ready for insertion.
     * @throws AuraHandledException if any validation or security access issues occur.
     */
    private static List<OrderItem> prepareOrderItems(Order order, List<Object> productEntries, Map<Id, Map<String, Object>> pricebookEntryMap) {
        List<OrderItem> itemsToInsert = new List<OrderItem>();

        for (Object o : productEntries) {
            Map<Object, Object> productEntry = (Map<Object, Object>) o;
            Id productId = (Id) (String) productEntry.get('productId');
            Integer quantity = Integer.valueOf((Decimal) productEntry.get('quantity'));

            if (productId == null || quantity == null || quantity <= 0) {
                throw new AuraHandledException(CLA_FormConstants.ERR_INVALID_PRODUCT_ENTRY);
            }

            if (!pricebookEntryMap.containsKey(productId)) {
                throw new AuraHandledException(CLA_FormConstants.ERR_PRICEBOOKENTRY_NOT_FOUND + productId);
            }

            Map<String, Object> pricing = pricebookEntryMap.get(productId);
            itemsToInsert.add(new OrderItem(
                OrderId = order.Id,
                Quantity = quantity,
                PricebookEntryId = (Id) pricing.get('entryId'),
                Product2Id = productId,
                UnitPrice = (Decimal) pricing.get('unitPrice')
            ));
        }

        return itemsToInsert;
    }

    /**
     * Creates an Order and associated OrderItems for a Person Account based on input data.
     * 
     * @param input A map containing the necessary data to create the account, order, and items.
     * @throws AuraHandledException if any validation or field security error occurs.
     */
    public static void createOrderWithItems(Map<String, Object> input) {
        try {
            String email = (String) input.get('email');
            Boolean optIn = input.containsKey('optInAnnualNewsletter') ? (Boolean) input.get('optInAnnualNewsletter') : null;
            Boolean pink2022 = input.containsKey('wishlistVintagePink2022') ? (Boolean) input.get('wishlistVintagePink2022') : false;
            List<Object> wishlistSelections = (List<Object>) input.get('wishlistSelections');
            List<Object> productEntries = (List<Object>) input.get('products');
            String campaignId  = (String) input.get('campaignId');
            String retailerIdStr = input.containsKey('retailerId') ? (String) input.get('retailerId') : null;
            String retailerNameText = input.containsKey('retailerNameText') ? (String) input.get('retailerNameText') : null;
            Id retailerId;

            Boolean hasProducts = (productEntries != null && !productEntries.isEmpty());
            Boolean hasWishlist = (wishlistSelections != null && !wishlistSelections.isEmpty());
    
            if (String.isBlank(email)) {
                AuraHandledException e = new AuraHandledException(CLA_FormConstants.ERR_EMAIL_REQUIRED);
                e.setMessage(CLA_FormConstants.ERR_EMAIL_REQUIRED);
                throw e;
            }
            if (!hasProducts && !hasWishlist) {
                AuraHandledException e = new AuraHandledException(CLA_FormConstants.ERR_PRODUCTS_REQUIRED);
                e.setMessage(CLA_FormConstants.ERR_PRODUCTS_REQUIRED);
                throw e;
            }
            if (!Schema.sObjectType.OrderItem.isCreateable()) {
                AuraHandledException e = new AuraHandledException(CLA_FormConstants.ERR_ORDERITEM_CREATE);
                e.setMessage(CLA_FormConstants.ERR_ORDERITEM_CREATE);
                throw e;
            }

            if (String.isBlank(retailerIdStr) && !String.isBlank(retailerNameText)) {
                if (!Schema.sObjectType.Retailer__c.isCreateable()) {
                    throw new AuraHandledException('No permission to create Retailers.');
                }
                Retailer__c newRet = new Retailer__c(Name = retailerNameText);
                insert newRet;
                retailerId = newRet.Id;
            } else if (!String.isBlank(retailerIdStr)) {
                retailerId = (Id) retailerIdStr;
            }

            // Construct Person Account Input
            CLA_FormUtils.PersonAccountInput personInput = new CLA_FormUtils.PersonAccountInput();
            personInput.email = input.containsKey('email') ? (String) input.get('email') : null;
            personInput.optInNewsletter = input.containsKey('optInAnnualNewsletter') ? (Boolean) input.get('optInAnnualNewsletter') : false;
            personInput.firstName = input.containsKey('firstName') ? (String) input.get('firstName') : null;
            personInput.lastName = input.containsKey('lastName') ? (String) input.get('lastName') : null;
            personInput.phone = input.containsKey('phone') ? (String) input.get('phone') : null;
            personInput.birthdate = input.containsKey('birthdate') ? Date.valueOf((String) input.get('birthdate')) : null;
            personInput.region = input.containsKey('region') ? (String) input.get('region') : null;
            personInput.country = input.containsKey('country') ? (String) input.get('country') : null;
            personInput.state = input.containsKey('state') ? (String) input.get('state') : null;
            personInput.mailingStreet = input.containsKey('street') ? (String) input.get('street') : null;
            personInput.mailingCity = input.containsKey('city') ? (String) input.get('city') : null;
            personInput.mailingPostalCode = input.containsKey('zip') ? (String) input.get('zip') : null;


            // Obtain campaign
            Campaign campaign = new Campaign();
            if (!String.isBlank(campaignId)) {
                campaign = [SELECT Id, Name, Type FROM Campaign WHERE Id = :campaignId LIMIT 1];
                personInput.source = campaign.Type;
                personInput.subcategory = campaign.Name;
            }
    
            // Create or retrieve the Person Account
            Account personAccount = getOrCreatePersonAccount(personInput);
            // Create the Order
            Order order = createOrder(personAccount, input);
            // Prepare and Insert Order Items
            if (productEntries != null && !productEntries.isEmpty()) {
                Set<Id> productIds = new Set<Id>();
                for (Object o : productEntries) {
                    Map<Object, Object> prod = (Map<Object, Object>) o;
                    String productIdStr = (String) prod.get('productId');
                    if (String.isBlank(productIdStr)) {
                        AuraHandledException e = new AuraHandledException(CLA_FormConstants.ERR_PRODUCTID_MISSING);
                        e.setMessage(CLA_FormConstants.ERR_PRODUCTID_MISSING);
                        throw e;
                    }
                    productIds.add((Id) productIdStr);
                }
                Map<Id, Map<String, Object>> pricebookEntryMap = getPricebookEntryMap(productIds);
                List<OrderItem> orderItems = prepareOrderItems(order, productEntries, pricebookEntryMap);
                insert orderItems;
            }

            if (hasWishlist) {

                List<CLA_Interest__c> interests = new List<CLA_Interest__c>();

                if (wishlistSelections != null) {
                    for (Object o : wishlistSelections) {
                        Map<Object, Object> sel = (Map<Object, Object>) o;
                        String mainI = (String) sel.get('mainInterest');
                        String subI  = (String) sel.get('subInterest');
                        if (String.isBlank(mainI) || String.isBlank(subI)) continue;

                        interests.add(new CLA_Interest__c(
                            CLA_MainInterest__c = mainI,
                            CLA_Interest__c     = subI,
                            Account__c          = personAccount.Id
                        ));
                    }
                }

                if (!interests.isEmpty()) {
                    insert interests;
                }
            }
    
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug('Error: '+e.getMessage());
            System.debug('Stacktrace: '+e.getStackTraceString());
            System.debug('Line number: '+e.getLineNumber());
            throw new AuraHandledException('Failed to create order: ' + e.getMessage());
        }
    }
    
    /**
     * Creates an Order and associated OrderItems for a Person Account based on input data.
     * 
     * @param input A map containing the necessary data to create the waiting list record.
     * @throws AuraHandledException if any validation or field security error occurs.
     */
    private static void createWaitingListRecord(CLA_FormUtils.WaitingListInput input){
        try {
            Waiting_List__c waitingList = new Waiting_List__c(
                Account__c = input.accountId,
                CLA_Account_Source__c = input.accountSource,
                CLA_Source_Category__c = input.sourceCategory,
                CLA_Source_Sub_Category__c = input.sourceSubCategory
            );
            insert waitingList;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to create waiting list record: ' + e.getMessage());
        }
    }
    
    /**
     * Wrapper class to represent the input required for creating or retrieving a Person Account.
     */
    public class PersonAccountInput {
        @AuraEnabled public String email;
        @AuraEnabled public Boolean optInNewsletter;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String region;
        @AuraEnabled public String country;
        @AuraEnabled public String state;
        @AuraEnabled public String phone;
        @AuraEnabled public Date birthdate;
        @AuraEnabled public String source;
        @AuraEnabled public String subcategory;
        @AuraEnabled public String mailingStreet;
        @AuraEnabled public String mailingCity;
        @AuraEnabled public String mailingPostalCode;

    }

    /**
     * Wrapper class to represent the input required for creating a Waiting List Record.
     */
    public class WaitingListInput {
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountSource;
        @AuraEnabled public String sourceCategory;
        @AuraEnabled public String sourceSubCategory;
    }
}