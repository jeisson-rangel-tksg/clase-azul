/**
 * @description 
 * Centralizes all constant values used across the form-related utility classes. 
 * This includes record type developer names, default field values, and standardized error messages.
 * Using this class prevents hardcoding values and simplifies maintenance.
 *
 * @author 
 * Luis Vargas, Company: The KSquare Group
 * @date 
 * May 31, 2025
 */
public class CLA_FormConstants {
    public static final String RECORD_TYPE_PERSON_ACCOUNT = 'PersonAccount';
    public static final String RECORD_TYPE_ORDER_ALLOCATION = 'Allocation';
    public static final String DEFAULT_ACCOUNT_SOURCE = 'PRIVATE SALE';
    public static final String DEFAULT_SUBCATEGORY = 'MEXICO';
    public static final String DEFAULT_SOURCE = 'DIGITAL CELLAR';
    public static final String DEFAULT_ORDER_STATUS = 'Allocation';
    public static final String DEFAULT_ORDER_TYPE  = 'Allocation';

    public static final List<String> CANCELLED_STATUS_ORDER = new List<String>{'Cancelled - Post Payment', 'Cancelled'};    

    public static final String MAIN_INTEREST_PINK_2022 = 'LE';
    public static final String INTEREST_PINK_2022 = 'Pink 2022';

    public static final String ERR_EMAIL_REQUIRED = 'Email is required.';
    public static final String ERR_PRODUCTS_REQUIRED = 'At least one product must be provided.';
    public static final String ERR_PRODUCTID_MISSING = 'Each product must include a productId.';
    public static final String ERR_PRICEBOOKENTRY_NOT_FOUND = 'No active PricebookEntry found for product ID: ';
    public static final String ERR_INVALID_PRODUCT_ENTRY = 'Each product must have a valid productId and a quantity > 0.';
    public static final String ERR_STANDARD_PRICEBOOK_NOT_FOUND = 'Standard pricebook not found.';
    public static final String ERR_ACCOUNT_CREATE = 'No permission to create Accounts.';
    public static final String ERR_ACCOUNT_UPDATE = 'No permission to update Accounts.';
    public static final String ERR_ORDER_CREATE = 'No permission to create Orders.';
    public static final String ERR_ORDERITEM_CREATE = 'No permission to create Order Items.';
    public static final String ERR_MISSING_CAMPAIGNID = 'Campaign Id is missing';

    // Default pickup locations used in case the campaign record has no location selected
    public static final String DEFAULT_PICKUP_LOCATION_OPTIONS = 'Cabos;Loft Boutique;E-commerce';
}