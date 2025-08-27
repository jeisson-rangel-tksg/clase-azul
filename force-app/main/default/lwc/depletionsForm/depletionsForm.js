import { LightningElement, track } from 'lwc';
import validateAccount from '@salesforce/apex/DepletionsFormController.validateAccount';
import createDepletions from '@salesforce/apex/DepletionsFormController.createDepletions';
import getProductName from '@salesforce/apex/DepletionsFormController.getProductName';
import getThirdpartySellerName from '@salesforce/apex/DepletionsFormController.getThirdpartySellerName';
import createThirdPartySeller from '@salesforce/apex/DepletionsFormController.createThirdPartySeller';
import getTypePicklistValues from '@salesforce/apex/DepletionsFormController.getTypePicklistValues';
import { loadScript } from 'lightning/platformResourceLoader';
import PapaParse from '@salesforce/resourceUrl/papaparse';
import getProductCodeToIdMap from '@salesforce/apex/DepletionsFormController.getProductCodeToIdMap';
import getSellerNameToIdMap from '@salesforce/apex/DepletionsFormController.getSellerNameToIdMap';

export default class DepletionsForm extends LightningElement {
    @track taxId = '';
    @track email = '';
    @track accountId;
    @track showForm = false;

    @track thirdPartySellerId = '';
    @track productId = '';
    @track productName = '';
    @track thirdPartyName = '';
    @track country = '';
    @track city = '';
    @track state = '';

    @track depletionList = [];

    @track isNoAccountModalOpen = false;
    @track isSuccessModalOpen = false;
    @track isErrorModalOpen = false;
    @track isMissingFieldsModalOpen = false;

    @track isEditModalOpen = false;
    @track editDepletion = {};

    @track isNewSeller = false;
    @track newThirdPartySellerName = '';

    @track quantity = '';
    @track type = '';
    @track typeOptions = [];

    @track showProductPicker = true;
    @track showThirdPartyPicker = true;

    @track isCSVErrorModalOpen = false;
    @track uploadErrors = [];

    columns = [
        { label: 'Product', fieldName: 'productName' },
        { label: 'Third Party Seller', fieldName: 'thirdPartySellerName' },
        { label: 'City', fieldName: 'city' },
        { label: 'State', fieldName: 'state' },
        { label: 'Quantity', fieldName: 'quantity' },
        { label: 'Type', fieldName: 'type' },
        {
            type: 'action',
            typeAttributes: {
                rowActions: [
                    { label: 'Edit', name: 'edit' },
                    { label: 'Remove', name: 'remove' }
                ]
            }
        }
    ];

    productMatchingInfo = {
        primaryField: { fieldPath: 'ProductCode' }
    };

    thirdPartyMatchingInfo = {
        primaryField: { fieldPath: 'Name' }
    };

    handleTaxIdChange(e) { this.taxId = e.target.value; }

    handleEmailChange(e) { this.email = e.target.value; }

    handleThirdPartySellerChange(e) {
        this.thirdPartyName = e.detail.label;
        this.thirdPartySellerId = e.detail.recordId; 
    }

    handleProductChange(e) { 
        this.productName = e.detail.label;
        this.productId = e.detail.recordId; 
    }

    handleCountryChange(e) {
        this.country = e.target.value;
    }

    handleCityChange(e) { this.city = e.target.value; }

    handleStateChange(e) { this.state = e.target.value; }

    handleTypeChange(e) {
        this.type = e.detail.value;
    }

    handleQuantityChange(e) {
        this.quantity = e.target.value;
    }

    handleToggleNewSeller(e) {
        this.isNewSeller = e.target.checked;
        this.thirdPartySellerId = '';
        this.thirdPartyName = '';
    }

    handleNewSellerNameChange(e) {
        this.newThirdPartySellerName = e.target.value;
    }

    handleEditProductChange(e) {
        this.editDepletion.productId = e.detail.recordId;
        this.editDepletion.productName = e.detail.label;
    }

    handleEditThirdPartyChange(e) {
        this.editDepletion.thirdPartySellerId = e.detail.recordId;
        this.editDepletion.thirdPartySellerName = e.detail.label;
    }

    handleEditCityChange(e) {
        this.editDepletion.city = e.target.value;
    }

    handleEditStateChange(e) {
        this.editDepletion.state = e.target.value;
    }

    handleEditQuantityChange(e) {
        this.editDepletion.quantity = e.target.value;
    }

    handleEditTypeChange(e) {
        this.editDepletion.type = e.detail.value;
    }

    handleSaveEdit() {
        this.depletionList = this.depletionList.map(d => {
            return d.id === this.editDepletion.id ? { ...this.editDepletion } : d;
        });
        this.isEditModalOpen = false;
    }

    handleImportClick() {
        this.template.querySelector('.csv-upload-input').click();
    }

    renderedCallback() {
        if (this.papaLoaded) return;
        this.papaLoaded = true;
        loadScript(this, PapaParse)
            .then(() => console.log('PapaParse loaded'))
            .catch(error => console.error('PapaParse load error', error));
    }

    connectedCallback() {
        getTypePicklistValues()
            .then(data => {
                this.typeOptions = data.map(value => ({
                    label: value,
                    value: value
                }));
            })
            .catch(error => {
                console.error('Failed to fetch Type picklist values', error);
            });
    }

    handleValidate() {
        validateAccount({ taxId: this.taxId, email: this.email })
            .then(result => {
                if (result) {
                    this.accountId = result;
                    this.showForm = true;
                } else {
                    this.isNoAccountModalOpen = true;
                }
            })
            .catch(() => this.isErrorModalOpen = true);
    }

    handleAddDepletion() {
        if (
            !this.productId ||
            (!this.isNewSeller && !this.thirdPartySellerId) ||
            (this.isNewSeller && !this.newThirdPartySellerName) ||
            !this.city ||
            !this.state ||
            this.type === '' ||
            this.quantity === ''
        ) {
            this.isMissingFieldsModalOpen = true;
            return;
        }

        // Create new Thirdparty Seller if selected by user
        const getSeller = this.isNewSeller
            ? createThirdPartySeller({ name: this.newThirdPartySellerName }).then(id => ({
                id,
                name: this.newThirdPartySellerName
            }))
            : getThirdpartySellerName({ thirdPartySellerId: this.thirdPartySellerId }).then(name => ({
                id: this.thirdPartySellerId,
                name
            }));

        // Also get product name
        Promise.all([
            getProductName({ productId: this.productId }),
            getSeller
        ])
        .then(([productName, sellerData]) => {
            const newDepletion = {
                id: Date.now().toString(),
                accountId: this.accountId,
                productId: this.productId,
                productName: productName,
                thirdPartySellerId: sellerData.id,
                thirdPartySellerName: sellerData.name,
                country: this.country,
                city: this.city,
                state: this.state,
                type: this.type,
                quantity: this.quantity
            };

            this.depletionList = [...this.depletionList, newDepletion];

            // Clear fields
            this.city = '';
            this.state = '';
            this.type = '';
            this.quantity = '';
            this.newThirdPartySellerName = '';
            this.thirdPartyName = '';
            this.resetPickers();
        })
        .catch(error => {
            console.error('Failed to fetch product or seller:', error);
            this.isErrorModalOpen = true;
        });
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if (actionName === 'remove') {
            this.depletionList = this.depletionList.filter(d => d.id !== row.id);
        } else if (actionName === 'edit') {
            this.editDepletion = { ...row };
            this.isEditModalOpen = true;
        }
    }

    handleSubmit() {
        const payload = this.depletionList.map(d => ({
            accountId: d.accountId,
            productId: d.productId,
            thirdPartySellerId: d.thirdPartySellerId,
            country: d.country,
            city: d.city,
            state: d.state,
            type: d.type,
            quantity: parseInt(d.quantity, 10)
        }));

        console.log('PAYLOAD:', JSON.stringify(payload));

        createDepletions({ depletions: payload })
            .then(() => {
                this.depletionList = [];
                this.isSuccessModalOpen = true;
            })
            .catch(error => {
                console.error('ERROR:', JSON.stringify(error));
                this.errorMessage = error?.body?.message || 'Unexpected error';
                this.isErrorModalOpen = true;
            });
    }

    async handleFileUpload(event) {
        const file = event.target.files[0];
        if (!file) return;

        // Ensure JS library is loaded
        if (!this.papaLoaded) {
            try {
                await loadScript(this, PapaParse);
                this.papaLoaded = true;
            } catch (e) {
                this.isErrorModalOpen = true;
                event.target.value = null;
                return;
            }
        }

        // Helpers
        const readFileAsText = (f) => new Promise((resolve, reject) => {
            const r = new FileReader();
            r.onload = () => resolve(r.result);
            r.onerror = reject;
            r.readAsText(f);
        });
        const isIntInRange = (v, min, max) => {
            const n = Number(v);
            return Number.isInteger(n) && n >= min && n <= max;
        };

        try {
            // Read and parse csv
            const csvText = await readFileAsText(file);
            const parsed = window.Papa.parse(csvText, { header: true, skipEmptyLines: true });

            if (parsed.errors?.length) {
                this.uploadErrors = parsed.errors.map(er => `Row ${er.row + 1}: ${er.message}`);
                this.isCSVErrorModalOpen = true;
                event.target.value = null;
                return;
            }

            const rows = parsed.data || [];

            // Get lookup parameters
            const productCodes = [...new Set(rows.map(r => (r['Product SKU'] || '').trim()).filter(Boolean))];
            const sellerNames  = [...new Set(rows.map(r => (r['Distributor'] || '').trim()).filter(Boolean))];

            if (productCodes.length === 0 && sellerNames.length === 0) {
                this.uploadErrors = ['CSV has no values for "Product SKU" or "Distributor".'];
                this.isCSVErrorModalOpen = true;
                event.target.value = null;
                return;
            }

            // Lookup for records on salesforce
            const [productMap, sellerMap] = await Promise.all([
                getProductCodeToIdMap({ productCodes }),
                getSellerNameToIdMap({ sellerNames })
            ]);

            // Validate & build rows
            const allowedTypes = new Set((this.typeOptions || []).map(o => o.value));
            const rowErrors = [];
            const parsedDepletions = [];

            rows.forEach((row, idx) => {
                const line = idx + 2;
                const sku = (row['Product SKU'] || '').trim();
                const distributor = (row['Distributor'] || '').trim();
                const country = row['Country'] || '';
                const city = row['City'] || '';
                const state = row['State'] || '';
                const type = (row['Case/Bottles'] || '').trim();
                const qtyRaw = row['Quantity'];

                if (!sku) rowErrors.push(`Line ${line}: Missing Product SKU`);
                if (!distributor) rowErrors.push(`Line ${line}: Missing Distributor`);
                if (!type) rowErrors.push(`Line ${line}: Missing Case/Bottles`);
                if (!isIntInRange(qtyRaw, 1, 99999)) rowErrors.push(`Line ${line}: Quantity must be an integer between 1 and 99999`);
                if (allowedTypes.size && type && !allowedTypes.has(type)) {
                    rowErrors.push(`Line ${line}: Type "${type}" is not a valid option`);
                }

                const productId = productMap[sku];
                if (!productId) rowErrors.push(`Line ${line}: Product SKU "${sku}" not found`);

                const sellerId = sellerMap[distributor];
                if (!sellerId) rowErrors.push(`Line ${line}: Distributor "${distributor}" not found`);

                // Skip adding if invalid
                if (!productId || !sellerId || !isIntInRange(qtyRaw, 1, 99999) || !type) return;

                parsedDepletions.push({
                    id: Date.now().toString() + idx,
                    accountId: this.accountId,
                    country, city, state,
                    quantity: String(qtyRaw).trim(),
                    type,
                    productId,
                    productName: sku,
                    thirdPartySellerId: sellerId,
                    thirdPartySellerName: distributor
                });
            });

            // Show partial row errors (non-fatal)
            if (rowErrors.length) {
                this.uploadErrors = rowErrors;
                this.isCSVErrorModalOpen = true;
            }

            // Append valid rows
            if (parsedDepletions.length) {
                this.depletionList = [...this.depletionList, ...parsedDepletions];
            }
        } catch (err) {
            const e = JSON.parse(JSON.stringify(err));
            console.error('Lookup failure (detail):', e);
            const msg = e?.body?.message || e?.message || 'Lookup failed';
            this.uploadErrors = [`CSV lookup failed: ${msg}`];
            this.isCSVErrorModalOpen = true;
        } finally {
            event.target.value = null;
        }
    }


    closeModals() {
        this.isNoAccountModalOpen = false;
        this.isSuccessModalOpen = false;
        this.isErrorModalOpen = false;
        this.isMissingFieldsModalOpen = false;
    }

    closeEditModal() {
        this.isEditModalOpen = false;
    }

    closeCSVErrorModal() {
        this.isCSVErrorModalOpen = false;
        this.uploadErrors = [];
    }

    resetPickers() {
        this.productId = '';
        this.thirdPartySellerId = '';

        // Temporarily hide, then show again to force re-render
        this.showProductPicker = false;
        this.showThirdPartyPicker = false;

        setTimeout(() => {
            this.showProductPicker = true;
            this.showThirdPartyPicker = true;
        }, 10); // small delay to allow DOM reflow
    }
}