import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

//import getPickupLocationsFromCampaign from '@salesforce/apex/CLA_FormVPMPController.getPickupLocationsFromCampaign';
//import getPickupLocationsFromCampaignAlmacenes from '@salesforce/apex/CLA_FormVPMPController.getPickupLocationsFromCampaignAlmacenes';
//import getCampaignProducts from '@salesforce/apex/CLA_FormVPMPController.getCampaignProducts';
import getPersonAccountByEmail from '@salesforce/apex/CLA_FormVPMPController.getPersonAccountByEmail';
import createOrders from '@salesforce/apex/CLA_FormVPMPController.createOrders';
import getPickupLocationsAndProductsByCampaign from '@salesforce/apex/CLA_FormVPMPController.getPickupLocationsAndProductsByCampaign';
import isCampaignActive from '@salesforce/apex/CLA_FormVPMPController.isCampaignActive';
import updateMissingAccountFields from '@salesforce/apex/CLA_FormVPMPController.updateMissingAccountFields';
import { getObjectInfo, getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import ACCOUNT_OBJECT from '@salesforce/schema/Contact';
import REGION_FIELD from '@salesforce/schema/Contact.Region__c';
import COUNTRY_FIELD from '@salesforce/schema/Contact.Country__c';
import STATE_FIELD from '@salesforce/schema/Contact.State__c';


export default class CampaignOrderComponent extends LightningElement {
    // Core Fields
    email = '';
    campaignId;
    accountId = '';
    selectedPickupLocation = '';
    optInAnnualNewsletter = false;
    products = [];

    // Person Info
    firstName = '';
    lastName = '';
    birthdate = '';
    phone = '';
    city = '';
    zip = '';

    // UI State
    isLoading = true;
    isComponentReady = false;
    isNewOrderOpen = false;
    isNoExistingAccountModalOpen = false;
    isInvalidCampaignModalOpen = false;
    @track showCountryInput = false;
    @track showStateInput = false;
    @track isPickupLocationDisabled = false;


    // Picklists
    @track pickupLocationOptions = [];

    @track productsByLocation = {};

    @track regionOptions = [];
    @track countryOptions = [];
    @track stateOptions = [];

    @track selectedRegion = '';
    @track country = '';
    @track state = '';

    @track isEmailDisabled = false;
    isEmailFromUrl = false;

    // Account fields
    @track showMissingBirthdate = false;
    @track showMissingLocationFields = false;

    recordTypeId;
    countryFieldInfo;
    stateFieldInfo;

    @wire(getObjectInfo, { objectApiName: ACCOUNT_OBJECT })
    objectInfo({ data }) {
        if (data) {
            this.recordTypeId = data?.defaultRecordTypeId;
        }
    }

    @wire(getPicklistValuesByRecordType, { objectApiName: ACCOUNT_OBJECT, recordTypeId: '$recordTypeId' })
    picklistValues({ data, error }) {
        if (data) {
            this.regionOptions = data.picklistFieldValues[REGION_FIELD.fieldApiName]?.values || [];
            this.countryFieldInfo = data.picklistFieldValues[COUNTRY_FIELD.fieldApiName];
            this.stateFieldInfo = data.picklistFieldValues[STATE_FIELD.fieldApiName];
        } else if (error) {
            console.error('Error fetching picklist values:', JSON.parse(JSON.stringify(error)));
        }
    }

    @wire(CurrentPageReference)
    getUrlParams(currentPageReference) {
        if (currentPageReference) {
            const email = currentPageReference.state?.email || '';
            const campaignId = currentPageReference.state?.campaignId || '';

            if (email) {
                this.email = email;
                this.isEmailFromUrl = true;
            }
            if (campaignId) this.campaignId = campaignId;

            if (this.campaignId) {
                isCampaignActive({ campaignId: this.campaignId })
                    .then(result => {
                        if (!result) {
                            // inactive campaign → show modal
                            this.isInvalidCampaignModalOpen = true;
                            this.isLoading = false;
                        } else {
                            // active → continue as usual
                            this.checkAccount();
                        }
                    })
                    .catch(error => {
                        console.error('Error checking campaign active:', error);
                        this.isInvalidCampaignModalOpen = true;
                        this.isLoading = false;
                    });
            } else {
                this.isInvalidCampaignModalOpen = true;
                this.isLoading = false;
            }

        }
    }

    // -------------------------------
    // Loaders
    // -------------------------------
    initializeComponent() {
        getPickupLocationsAndProductsByCampaign({ campaignId: this.campaignId })
        .then(result => {
            console.log(JSON.stringify(result));
            this.pickupLocationOptions = result.pickupLocations || [];
            this.productsByLocation = result.productsByLocation || {};

            if (this.pickupLocationOptions.length === 1) {
                this.selectedPickupLocation = this.pickupLocationOptions[0].value;
                this.isPickupLocationDisabled = true;
                this.products = this.mapProducts(this.productsByLocation[this.selectedPickupLocation] || []);
            }

            this.isComponentReady = true;
        })
        .catch(error => {
            console.error('Error loading campaign data:', error);
            this.isInvalidCampaignModalOpen = true;
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    checkAccount() {
        const isValidEmail = this.email?.trim() !== '';
        if (!isValidEmail) {
            this.isLoading = false;
            this.initializeComponent();
            return;
        }

        this.fetchAccountByEmail().finally(() => this.initializeComponent());
    }

    fetchAccountByEmail() {
        const trimmedEmail = this.email?.trim();
        if (!trimmedEmail) {
            return Promise.resolve();
        }

        this.isLoading = true;
        return getPersonAccountByEmail({ email: trimmedEmail })
            .then(result => {
                this.accountId = result?.accountId || '';
                this.optInAnnualNewsletter = result?.optInAnnualNewsletter || false;

                const bdate = result?.birthdate;
                const region = result?.region;
                const country = result?.country;
                const state = result?.state;

                this.showMissingBirthdate = !bdate;
                this.showMissingLocationFields = !region || !country || !state;

                if (this.accountId && this.isEmailFromUrl) {
                    this.isEmailDisabled = true;
                } else {
                    this.isEmailDisabled = false;
                }
            })
            .catch(error => {
                console.error('Error fetching account by email:', error);
                this.optInAnnualNewsletter = false;
                this.isEmailDisabled = false;
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    mapProducts(rawProducts) {
        return rawProducts.map(product => ({
            ...product,
            quantity: 0,
            selected: false,
            disabled: true,
            maxQuantity: product.Family === 'E. Limitadas' ? 2 : 4
        }));
    }

    updateCountryOptions() {
        if (this.countryFieldInfo && this.selectedRegion) {
            const controllingValueIndex = this.countryFieldInfo.controllerValues[this.selectedRegion];
            const filteredCountries = this.countryFieldInfo.values.filter(opt =>
                opt.validFor.includes(controllingValueIndex)
            );

            this.countryOptions = filteredCountries;

            if (filteredCountries.length <= 2) {
                this.showCountryInput = true;
                this.showStateInput = true; 
            } else {
                this.showCountryInput = false;
                this.showStateInput = false;
            }
        } else {
            this.countryOptions = [];
            this.showCountryInput = false;
        }
    }

    updateStateOptions() {
        if (this.showCountryInput) {
            this.showStateInput = true;
            return;
        }
    
        if (this.stateFieldInfo && this.country) {
            const controllingValueIndex = this.stateFieldInfo.controllerValues[this.country];
            const filteredStates = this.stateFieldInfo.values.filter(opt =>
                opt.validFor.includes(controllingValueIndex)
            );
    
            this.stateOptions = filteredStates;
    
            if (filteredStates.length <= 2) {
                this.showStateInput = true;
            } else {
                this.showStateInput = false;
            }
        } else {
            this.stateOptions = [];
            this.showStateInput = false;
        }
    }

    // -------------------------------
    // Handlers
    // -------------------------------
    handleRegionChange(event) {
        this.selectedRegion = event.target.value;
        this.country = '';
        this.state = '';
        this.stateOptions = [];
        this.updateCountryOptions();
    }
    
    handleCountryChange(event) {
        this.country = event.target.value;
        this.state = '';
        this.updateStateOptions();
    }
    
    handleStateChange(event) {
        this.state = event.target.value;
    }

    handleEmailBlur(event) {
        const newValue = event.target.value?.trim();
        if (!newValue || newValue === this.email) {
            this.isLoading = false;
            return;
        }

        this.email = newValue;
        this.fetchAccountByEmail();
    }

    handleInputChange(event) {
        const { name, value } = event.target;
        this[name] = value;
        if (name === 'selectedPickupLocation') {
        this.products = this.mapProducts(this.productsByLocation[value] || []);
}
    }

    handleCheckboxChange(event) {
        this.optInAnnualNewsletter = event.target.checked;
    }

    handleProductCheckboxChange(event) {
        const index = event.target.dataset.index;
        const updatedProducts = [...this.products];

        const isChecked = event.target.checked;
        updatedProducts[index].selected = isChecked;
        updatedProducts[index].quantity = 0;
        updatedProducts[index].disabled = !isChecked;

        this.products = updatedProducts;
    }

    handleQuantityChange(event) {
        const index = event.target.dataset.index;
        const updatedProducts = [...this.products];

        if (!updatedProducts[index].selected) return;

        let quantity = parseInt(event.target.value, 10) || 0;
        //const max = updatedProducts[index].maxQuantity;
        //if (quantity > max) quantity = max;
        //updatedProducts[index].quantity = Math.min(quantity, max);
        updatedProducts[index].quantity = quantity;
        this.products = updatedProducts;
    }

    handleSubmit() {
        if (!this.email) {
            this.showToast('Error', 'Missing customer email.', 'error');
            return;
        }

        const formattedProducts = this.products
            .filter(prod => parseInt(prod.quantity, 10) > 0)
            .map(prod => ({
                productId: prod.Id,
                quantity: parseInt(prod.quantity, 10)
            }));

        if (formattedProducts.length === 0) {
            this.showToast('Error', 'No products selected.', 'error');
            return;
        }

        const rawRequest = {
            email: this.email,
            optInAnnualNewsletter: this.optInAnnualNewsletter,
            firstName: this.firstName,
            lastName: this.lastName,
            region: this.selectedRegion,
            country: this.country,
            state: this.state,
            phone: this.phone,
            birthdate: this.birthdate,
            city: this.city,
            zip: this.zip,
            campaignId: this.campaignId,
            pickupLocation: this.selectedPickupLocation,
            products: formattedProducts
        };
        
        // Filter out null or undefined fields
        const orderRequest = Object.fromEntries(
            Object.entries(rawRequest).filter(([_, v]) => v !== null && v !== undefined && String(v).trim() !== '')
        );

        this.isLoading = true;
        createOrders({ input: orderRequest })
            .then(() => {
            this.isNewOrderOpen = true;
            this.products = this.mapProducts(this.products);

            if (this.accountId && (this.showMissingBirthdate || this.showMissingLocationFields)) {
                const updatePayload = {
                    accountId: this.accountId
                };

                if (this.showMissingBirthdate && this.birthdate) updatePayload.birthdate = this.birthdate;
                if (this.showMissingLocationFields && this.selectedRegion) updatePayload.region = this.selectedRegion;
                if (this.showMissingLocationFields && this.country) updatePayload.country = this.country;
                if (this.showMissingLocationFields && this.state) updatePayload.state = this.state;

                // Fire update
                updateMissingAccountFields({ input: updatePayload })
                    .catch(err => console.error('Failed to update missing fields:', err));
            }
            })
            .catch(error => {
                console.error('Create order failed:', error);
                this.showToast('Error', error.body?.message || error.message, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // -------------------------------
    // Utility
    // -------------------------------
    get isNewUser() {
        return !this.accountId && this.email && this.email !== '';
    }

    get isSubmitDisabled() {
        return !this.isFormValid();
    }

    get submitButtonClass() {
        return this.isSubmitDisabled ? 'btn btn-cas custom-disabled' : 'btn btn-cas';
    }

    isFormValid() {
        const allValid = [...this.template.querySelectorAll('lightning-input, lightning-combobox')]
            .reduce((validSoFar, inputCmp) => validSoFar && inputCmp.checkValidity(), true);
        const hasSelectedProducts = this.products.some(prod => parseInt(prod.quantity, 10) > 0);
        return hasSelectedProducts && allValid;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}