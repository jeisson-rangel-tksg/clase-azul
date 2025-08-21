public with sharing class LeadConversionUtils {

    public static Account updateAccountInfoFromLead(Id leadId, Id accountId) {
        Lead l = [
            SELECT Birthday__c, Category__c, City, Country, Country__c, Email, EmailBouncedDate, EmailBouncedReason,
                et4ae5__HasOptedOutOfMobile__c, et4ae5__Mobile_Country_Code__c, GeocodeAccuracy, HasOptedOutOfEmail, IndividualId,
                Industry, Jigsaw, LastReferencedDate, Latitude, Longitude, LeadSource, MobilePhone, NumberOfEmployees, Phone,
                PhotoUrl, PostalCode, Region__c, Salutation, State, State__c, Street, Sub_Category__c, Suffix, Title, Website, Zipcode__c
            FROM Lead
            WHERE Id = :leadId
        ];

        Account acc = new Account(Id = accountId);
        acc.PersonBirthdate = l.Birthday__c;
        acc.PersonMailingCity = l.City;
        acc.PersonMailingCountry = l.Country;
        acc.Country__pc = l.Country__c;
        acc.PersonEmail = l.Email;
        acc.PersonEmailBouncedDate = l.EmailBouncedDate;
        acc.PersonEmailBouncedReason = l.EmailBouncedReason;
        acc.PersonMobilePhone = l.MobilePhone;
        acc.PersonMailingPostalCode = l.PostalCode;
        acc.PersonMailingState = l.State;
        acc.PersonMailingStreet = l.Street;
        acc.PersonMailingGeocodeAccuracy = l.GeocodeAccuracy;
        acc.PersonMailingLatitude = l.Latitude;
        acc.PersonMailingLongitude = l.Longitude;
        acc.PersonHasOptedOutOfEmail = l.HasOptedOutOfEmail;
        acc.PersonIndividualId = l.IndividualId;
        acc.PersonTitle = l.Title;
        acc.CLA_Fuente__c = l.Category__c;
        acc.CLA_SubCategory__c = l.Sub_Category__c;
        acc.Region__pc = l.Region__c;
        acc.Zip_Code__pc = l.Zipcode__c != null ? String.valueOf(l.Zipcode__c) : '';
        acc.et4ae5__HasOptedOutOfMobile__pc = l.et4ae5__HasOptedOutOfMobile__c;
        acc.et4ae5__Mobile_Country_Code__pc = l.et4ae5__Mobile_Country_Code__c;
        acc.State__pc = l.State__c;
        acc.AccountSource = l.LeadSource;
        acc.Industry = l.Industry;
        acc.Phone = l.Phone;
        acc.NumberOfEmployees = l.NumberOfEmployees;
        acc.Website = l.Website;
        acc.Jigsaw = l.Jigsaw;
        acc.Salutation = l.Salutation;
        acc.Suffix = l.Suffix;
        return acc;
    }


}