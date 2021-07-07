/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 07-07-2021
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
 * Modifications Log 
 * Ver   Date         Author                               Modification
 * 1.0   06-24-2021   ChangeMeIn@UserSettingsUnder.SFDoc   Initial Version
**/
public without sharing class LeadService
{

    public static final String DECISION_DECLINE = 'Decline';
    public static final String LOST_LEAD        = 'Closed Lost';
    
    public static final String LEAD_RT_CONSUMER = 'Consumer_Lead';
    public static final String LEAD_RT_REFERRED = 'Referred_Lead';

    public static final String LEAD_STATUS_PREAPPLICATION     = 'Pre-Application';
    public static final String LEAD_STATUS_ASSIGNED     = Label.Lead_Status_Assigned;
    public static final String LEAD_STATUS_CLOSEDLOST   = Label.Lead_Status_ClosedLost;

    public static final String LEAD_CHANNEL_CONSUMER    = Label.Lead_Channel_Consumer;
    public static final String LEAD_CHANNEL_REFERRED    = Label.Lead_Channel_Referred;
    public static final String LEAD_CHANNEL_WEALTH      = Label.Lead_Channel_Wealth;
    public static final String LEAD_CHANNEL_MRTG_BRK    = Label.Lead_Channel_MrtgBrk;
    
    public static Boolean inhibitQuoteCallout = false;

    public static Boolean isLeadConversion = false;

    public static Map<String, String> contactPC = new Map<String, String>{
        ContactHandler.CONTACT_RT_BANKER => LEAD_CHANNEL_REFERRED,
        ContactHandler.CONTACT_RT_MORTGAGE_BROKER => LEAD_CHANNEL_MRTG_BRK,
        ContactHandler.CONTACT_RT_WEALTH_PARTNER => LEAD_CHANNEL_WEALTH 
    };
    
    /*
        HEB-317: Update the Record type on the property so that value can be used for sharing
    */
    public static void setPropertyFileRecordType(List<Lead> newLeads, Map<Id, Lead> oldRecords)
    {
        Set<String> fieldsToCheck = new Set<String>{'Property__c'};

        List<Lead> ls = (List<Lead>) Utils.getChangedObjects(newLeads, oldRecords, fieldsToCheck);

        if ( oldRecords.isEmpty() ) ls.addAll( newLeads );
        
        Map<Id, Lead> propertyLeadMap = new Map<Id, Lead>();
        List<Property__c> propertyUpdateList = new List<Property__c>();

        for ( Lead ld : [SELECT Id, Property__c, RecordType.Name FROM Lead WHERE Id IN: ls ] )
        {
            if ( ld.Property__c != null) 
            {
                propertyLeadMap.put( ld.Property__c, ld );
            }
        }

        if (propertyLeadMap.isEmpty()) return;

        for (  Property__c prop : [ SELECT Id, File_Record_Type__c 
                                    FROM Property__c
                                    WHERE Id IN: propertyLeadMap.keySet()
        ])
        {
            prop.File_Record_Type__c = (propertyLeadMap.get(prop.Id).RecordType.Name).contains( Label.File_RecordType_Referred )
                                        ? Label.File_RecordType_Referred
                                        : Label.File_RecordType_Consumer ;
                                        
            propertyUpdateList.add(prop);
        }

        try 
        {
            update propertyUpdateList;
            
        } catch(DmlException e) {
            System.debug(e.getMessage());
        }

    }

    /*
        HEB-561: Update the Owner on Related records
    */
    public static void mapRelatedRecordsOwnership(List<Lead> newLeads, Map<Id, Lead> oldRecords)
    {
        Set<String> fieldsToCheck = new Set<String>{'OwnerId'};

        List<Lead> ls = (List<Lead>) Utils.getChangedObjects(newLeads, oldRecords, fieldsToCheck);
        Map<Id, Lead> leadMap = new MAp<Id, Lead>();

        for(Lead ld : ls) 
            leadMap.put( ld.Id, ld );

        if (leadMap.isEmpty() ) return;
            processRelatedRecordsOwnership(leadMap);
    }
        
    /*
     * HEB-878: re-fire ownership assignment if it fails
     */
    @future
    public static void retryRelatedRecordsOwership(List<Id> leadIds) {
        Map<Id, Lead> leadMap = new Map<Id, Lead>([select Id from Lead where Id IN :leadIds]);
        processRelatedRecordsOwnership(leadMap);
    }
    
    public static void processRelatedRecordsOwnership(Map<Id, Lead> leadMap)
    {
        List<Debt__c> debtList                  = new List<Debt__c>();
        List<Quote__c> quoteList                = new List<Quote__c>();
        List<Membership__c> membershipList      = new List<Membership__c>();
        List<Appraisal__c> appraisalList        = new List<Appraisal__c>();
        List<Appraisal_Order__c> apprOrderList  = new List<Appraisal_Order__c>();
        List<Property_Member__c> propertyMemList= new List<Property_Member__c>();
        List<Credit_Report__c> creditReportList = new List<Credit_Report__c>(); 
        Map<Id, Property__c> propertyList = new Map<Id, Property__c>();

        for (Lead l : [
            SELECT Id, OwnerId, Property__c, 
            (
            SELECT Id, Lead__c, OwnerId
                FROM Debts__r
            ),
            (
            SELECT Id, Lead__c, OwnerId
                FROM Quotes__r
            ),
            (
            SELECT Id, Lead__c, OwnerId
                FROM Memberships__r
            ),
            (
            SELECT Id, Lead__c, OwnerId
                FROM Appraisals__r
            ),
            (
            SELECT Id, Lead__c, OwnerId
                FROM Property_Members__r
            )
            FROM Lead
            WHERE Id IN :leadMap.keySet()
        ])
        {
            if(l.Property__c <> null)
                propertyList.put(l.Property__c, new Property__c(Id = l.Property__c, OwnerId = l.OwnerId));
            
            for (Debt__c debt : l.Debts__r)
            {
                if ( debt.OwnerId != leadMap.get(debt.Lead__c).OwnerId ){
                    debt.OwnerId         = leadMap.get(debt.Lead__c).OwnerId;
                    debtList.add(debt);
                }
            }
            for (Quote__c quote : l.Quotes__r)
            {
                if ( quote.OwnerId != leadMap.get(quote.Lead__c).OwnerId ){
                    quote.OwnerId        = leadMap.get(quote.Lead__c).OwnerId;
                    quoteList.add(quote);
                }
            }
            for (Membership__c membership : l.Memberships__r)
            {
                if ( membership.OwnerId != leadMap.get(membership.Lead__c).OwnerId){
                    membership.OwnerId   = leadMap.get(membership.Lead__c).OwnerId;
                    membershipList.add(membership);
                }
            }
            for (Appraisal__c appraisal : l.Appraisals__r)
            {
                if ( appraisal.OwnerId != leadMap.get(appraisal.Lead__c).OwnerId ){
                    appraisal.OwnerId    = leadMap.get(appraisal.Lead__c).OwnerId;
                    appraisalList.add(appraisal);
                }
            }
            
            for (Property_Member__c pm : l.Property_Members__r)
            {
                if ( pm.OwnerId != leadMap.get(pm.Lead__c).OwnerId ){
                    pm.OwnerId    = leadMap.get(pm.Lead__c).OwnerId;
                    propertyMemList.add(pm);
                }
            }    
        }

        for (Appraisal_Order__c apprOrder : [SELECT Id, Appraisal__c, Appraisal__r.Lead__c, OwnerId FROM Appraisal_Order__c 
                                            WHERE  Appraisal__r.Lead__c =: leadMap.keySet()])
        {
            if ( apprOrder.OwnerId  != leadMap.get(apprOrder.Appraisal__r.Lead__c).OwnerId ){
                apprOrder.OwnerId    = leadMap.get(apprOrder.Appraisal__r.Lead__c).OwnerId;
                apprOrderList.add(apprOrder);
            }
        }
        // Credit Report
        for (Credit_Report__c creditReport : [SELECT Id, Property_Member__r.Lead__c, OwnerId FROM Credit_Report__c WHERE Property_Member__r.Lead__c =: leadMap.keySet()])
        {   
            if ( creditReport.OwnerId  != leadMap.get(creditReport.Property_Member__r.Lead__c).OwnerId ){
                creditReport.OwnerId  = leadMap.get(creditReport.Property_Member__r.Lead__c).OwnerId;
                creditReportList.add( creditReport );
            }
        }

        Boolean reassignmentError = false;
        
        try{
            update propertyList.values();
        } catch ( Exception e ){
            reassignmentError = true;
            system.debug( e.getMessage() );
        }

        try{
            update debtList;
        } catch ( Exception e ){
            reassignmentError = true;
            system.debug( e.getMessage() );
        }

        try{
            update quoteList;
        } catch ( Exception e ){
            reassignmentError = true;
            system.debug( e.getMessage() );
        }

        try{
            update membershipList;
        } catch ( Exception e ){
            reassignmentError = true;
            system.debug( e.getMessage() );
        }

        try{
            update appraisalList;
        } catch ( Exception e ){
            reassignmentError = true;
            system.debug( e.getMessage() );
        }

        try{
            update apprOrderList;
        } catch ( Exception e ){
            reassignmentError = true;
            system.debug( e.getMessage() );
        }

        try{
            update propertyMemList;
        } catch ( Exception e ){
            reassignmentError = true;
            system.debug( e.getMessage() );
        }

        try{
            update creditReportList;
        } catch ( Exception e ){
                        //reassignmentError = true;  // Temp fix for CreditReport ownership change - Suppress the error indicator change. June 14, 2021
            system.debug( e.getMessage() );
        }

        // if there was an eror reassigning any of the records, queue up a retry
        if(reassignmentError) {
            List<Id> leadIds = new List<Id>();
            leadIds.addAll(leadMap.keySet());
            LeadOwnershipRetry updateJob = new LeadOwnershipRetry(leadIds);
            ID jobID = System.enqueueJob(updateJob);               
        }
    }

    
    /*
        HEB-247: When a lead is converted, ensure a Person Account is created for all Property Member records
    */
    public static void managePersonAccountsPostConversion(List<Lead> newLeads, Map<Id, Lead> oldLeadMap)
    {
        Map<Id, Lead> accountLeadMap = new Map<Id, Lead>();
        Map<Id, Lead> leadMap        = new Map<Id, Lead>();
        for (Lead l : newLeads)
        {
            if (l.IsConverted == true && oldLeadMap.get(l.Id).IsConverted == false)
            {
                accountLeadMap.put(l.ConvertedAccountId, l);
                leadMap.put(l.Id, l);
            }
        }
        
        // if no converted leads, no action
        if (accountLeadMap.isEmpty()) return;

        isLeadConversion = true;
        
        // Build a map of the relevant Property Member records
        Map<Id, Property_Member__c> propertyMemberMap = new Map<Id, Property_Member__c>([
            SELECT Id, Lead__c, CASL_Consent__c, CASL_Consent_Provided_On__c, CASL_Content_Obtained_By__c, Lead__r.Converted_Lead_Check__c, Person_Account__c, Email__c, Name__c, First_Name__c, Last_Name__c, Phone__c, Role__c, Date_of_Birth__c, Gender__c, Age__c, Is_Primary_Borrower__c
            FROM Property_Member__c
            WHERE Lead__c IN :accountLeadMap.values()
        ]);

        // Build a map of the Accounts created/updated in Lead conversion
        Map<String, Account> personAccountMap = new Map<String, Account>();
        for (Account a : [
            SELECT Id, FirstName, LastName, PersonEmail
            FROM Account
            WHERE Id IN :accountLeadMap.keySet()
            AND IsPersonAccount = true
        ])
        {
            personAccountMap.put(a.FirstName + '|' + a.LastName, a);
        }
        
        Map<String, Id> accountRecordTypes = Utils.getRecordTypeIdsBySObjectType(Account.SObjectType);

        Map<Id, Account> propertyMemberAccountMap = new Map<Id, Account>();
        
        Set<Id> usedAccountIds = new Set<Id>();
        for (Property_Member__c propertyMember : propertyMemberMap.values())
        {
            // Initialize a Person Account record for the Property Member
            Account a = new Account(
                RecordTypeId    = accountRecordTypes.get(AccountHandler.ACCOUNT_RT_CONSUMER),
                FirstName       = propertyMember.First_Name__c,
                LastName        = propertyMember.Last_Name__c,
                PersonEmail     = propertyMember.Email__c,
                Phone           = propertyMember.Phone__c,
                PersonBirthdate = propertyMember.Date_of_Birth__c,
                Gender__pc      = propertyMember.Gender__c,
                Age__pc         = propertyMember.Age__c,
                Converted_Lead_Check__c = propertyMember.Lead__r.Converted_Lead_Check__c,
                CASL_Consent_Provided_On__c     = propertyMember.CASL_Consent_Provided_On__c,
                CASL_Content_Obtained_By__c     = propertyMember.CASL_Content_Obtained_By__c,
                CASL_Consent__c     = propertyMember.CASL_Consent__c
            );

            /*
                 determine if this is the converted Lead
                     - if the Account Map has a value for this First Name/Last Name (matches an Account that the Lead was converted to)
                    - add check to ensure the same Account Id is not used multiple times
            */
            String pmKey = propertyMember.First_Name__c + '|' + propertyMember.Last_Name__c;
            if (
                personAccountMap.get(pmKey) <> null && 
                !usedAccountIds.contains(personAccountMap.get(pmKey).Id)
            ) {
               a.Id = personAccountMap.get(pmKey).Id;
               usedAccountIds.add(a.Id);
            }
            propertyMemberAccountMap.put(propertyMember.Id, a);
        }
        upsert propertyMemberAccountMap.values();
        
        //now that this is done, need to link the Person Accounts back to the Property Members
        for (Property_Member__c propertyMember : propertyMemberMap.values())
        {
            propertyMember.Person_Account__c = propertyMemberAccountMap.get(propertyMember.Id).Id;
            propertyMember.Opportunity__c    = leadMap.get(propertyMember.Lead__c).ConvertedOpportunityId;
        }
        update propertyMemberMap.values();
        
        // Also add a link between opportunity and person account to allow Pardot to pull the relationships.
        Map<Id, Id> personAccountContacts = new Map<Id, Id>();
        for (Contact c : [
            SELECT Id, AccountId
            FROM Contact
            WHERE AccountId IN :propertyMemberAccountMap.values()
        ])
        {
            personAccountContacts.put(c.AccountId, c.Id);
        }
        
        Map<String, OpportunityContactRole> existingOCRs = new Map<String, OpportunityContactRole>();
        for (OpportunityContactRole ocr : [
            SELECT Id, ContactId, OpportunityId
            FROM OpportunityContactRole
            WHERE ContactId IN :personAccountContacts.values()
        ]) {
            existingOCRs.put(ocr.ContactId + ':' + ocr.OpportunityId, ocr);
        }
        
        Map<String, OpportunityContactRole> ocrs = new Map<String, OpportunityContactRole>();
        for (Property_Member__c propertyMember : propertyMemberMap.values())
        {
            OpportunityContactRole ocr = new OpportunityContactRole(
                ContactId = personAccountContacts.get(propertyMember.Person_Account__c),
                OpportunityId = propertyMember.Opportunity__c,
                IsPrimary = propertyMember.Is_Primary_Borrower__c,
                Role = propertyMember.Role__c
            );
            
            String key = ocr.ContactId + ':' + ocr.OpportunityId;
            
            if (existingOCRs.containsKey(key))
                ocr.Id = existingOCRs.get(key).Id;
            
            ocrs.put(key, ocr);
        }
        
        upsert ocrs.values();
    }

    /*
        HEB-247: When a lead is converted, map all Debt/Appraisal/Quote records to the converted Opportunity
    */
    public static void mapRelatedRecordsPostConversion(List<Lead> newLeads, Map<Id, Lead> oldLeadMap)
    {
        Map<Id, Lead> leadMap       = new Map<Id, Lead>();
        for (Lead l : newLeads)
        {
            if (l.IsConverted == true && oldLeadMap.get(l.Id).IsConverted == false)
            {
                leadMap.put(l.Id, l);
            }
        }

        // if no converted leads, no action
        if (leadMap.isEmpty()) return;

        List<Debt__c> debtList                  = new List<Debt__c>();
        List<Quote__c> quoteList                = new List<Quote__c>();
        List<Membership__c> membershipList      = new List<Membership__c>();
        List<Appraisal__c> appraisalList        = new List<Appraisal__c>();
        for (Lead l : [
            SELECT Id,
            (
            SELECT Id, Lead__c, Opportunity__c
                FROM Debts__r
            ),
            (
            SELECT Id, Lead__c, Opportunity__c
                FROM Quotes__r
            ),
            (
            SELECT Id, Lead__c, Opportunity__c
                FROM Memberships__r
            ),
            (
            SELECT Id, Lead__c, Opportunity__c
                FROM Appraisals__r
            )
            FROM Lead
            WHERE Id IN :leadMap.keySet()
        ])
        {
            for (Debt__c debt : l.Debts__r)
            {
                debt.Opportunity__c         = leadMap.get(debt.Lead__c).ConvertedOpportunityId;
                debtList.add(debt);
            }
            for (Quote__c quote : l.Quotes__r)
            {
                quote.Opportunity__c        = leadMap.get(quote.Lead__c).ConvertedOpportunityId;
                quoteList.add(quote);
            }
            for (Membership__c membership : l.Memberships__r)
            {
                membership.Opportunity__c   = leadMap.get(membership.Lead__c).ConvertedOpportunityId;
                membershipList.add(membership);
            }
            for (Appraisal__c appraisal : l.Appraisals__r)
            {
                appraisal.Opportunity__c    = leadMap.get(appraisal.Lead__c).ConvertedOpportunityId;
                appraisalList.add(appraisal);
            }
        }
        update debtList;
        update quoteList;
        update membershipList;
        update appraisalList;
    }

    /*
        HEB-247: When a lead is converted, set the Opportunity Name to be Lead.Name " - " Lead.File_Number__c
    */
    public static void setConvertedLeadOpportunityName(List<Lead> newLeads, Map<Id, Lead> oldLeadMap)
    {
        Map<Id, Lead> oppLeadMap = new Map<Id, Lead>();
        for (Lead l : newLeads)
        {
            if (l.IsConverted == true && oldLeadMap.get(l.Id).IsConverted == false) 
            {
                oppLeadMap.put(l.ConvertedOpportunityId, l);
            }
        }

        // if no converted leads, no action
        if (oppLeadMap.isEmpty()) return;
        
        List<Opportunity> oppList = [
            SELECT Id, Name
            FROM Opportunity
            WHERE Id IN :oppLeadMap.keySet()
        ];

        // Create a list of opportunity ids
        List<id> oppIdList = new List<Id>();

        for(Opportunity o : oppList) {
            oppIdList.add(o.Id);
        }

        // Get a list of all pms that have that are primary borrowers
        List<Property_Member__c> pmcList = [SELECT Id, Last_Name__c, Opportunity__c FROM Property_Member__c WHERE Opportunity__c IN :oppIdList AND Is_Primary_Borrower__c = true];

        //Map the primary borrowers to opportunities
        Map<Id, String> pmIdNameMap = new Map<Id, String>(); 
        for(Property_Member__c pmc : pmcList) {
            pmIdNameMap.put(pmc.Opportunity__c, pmc.Last_Name__c);
        }

        for (Opportunity o : oppList) {
            //If there is no primary borrower set, use the lead last name
            if(pmIdNameMap.get(o.Id) == null){
                o.Name = oppLeadMap.get(o.Id).LastName + ' - ' + oppLeadMap.get(o.Id).File_Number__c;
            } else {
            // If there is a primary borrower set, use the borrower last name
                o.Name = pmIdNameMap.get(o.Id) + ' - ' + oppLeadMap.get(o.Id).File_Number__c;
            }
        }
        
        update oppList;
    }
    
    /*
    * Assigning the Lead to the Territory and Partner Account
    */ 
    public void assignToTerritorySpecialist(List<Lead> records)
    {
        Map<Id, Contact> partnerMap = new Map<Id, Contact>();
        
        for (Lead l : records)
        {
            if (l.Partner_Referrer__c != null)
            {
                partnerMap.put ( l.Partner_Referrer__c, new Contact());
            }
        }
        
        partnerMap.putAll([
            SELECT Id, Territory__c, Territory__r.SpecialistID__c, AccountId, RecordTypeId, OwnerId
            FROM Contact 
            WHERE Id IN: partnerMap.keySet()
        ]);
        if ( partnerMap.isEmpty() ) return;

        for (Lead l : records)
        {
            if (l.Partner_Referrer__c <> null)
            {
                Contact c                                = partnerMap.get(l.Partner_Referrer__c);
                if (l.Referral_Organization__c == null)  l.Referral_Organization__c  = c.AccountId;
                if (l.Territory__c == null)              l.Territory__c              = c.Territory__c;
                if (l.BDM__c == null)                    l.BDM__c                    = c.OwnerId;
                if (l.Channel__c == null)                l.Channel__c                = getContactPC(c.RecordTypeId);

                // Assign The lead Owner based on the Partner Referrer's Territory Specialist
                if ( c.Territory__c != null 
                    && c.Territory__r.SpecialistID__c != null 
                    && l.OwnerId != c.Territory__r.SpecialistID__c ) 
                {
                    l.OwnerId = c.Territory__r.SpecialistID__c != null
                        ? c.Territory__r.SpecialistID__c
                        : UserInfo.getUserId(); // Set the id to the running user if there is no specialist id
                }
            }
        }
    }

    /*
    *   HEB-317: Share records with BDM
    */
    public void shareLeadWithBDM(List<Lead> newLeads, Map<Id, Lead> oldRecords)
    {
        Set<String> fieldsToCheck       = new Set<String>{'BDM__c', 'OwnerId'};

        List<Lead> ls = (oldRecords == null) ?
            newLeads : 
            (List<Lead>) Utils.getChangedObjects(newLeads, oldRecords, fieldsToCheck);
        processBDMShares(ls);    
    }

    public void processBDMShares(List<Lead> ls)
    {
        Map<Id, Lead> leadMap          = new Map<Id, Lead>();
        List<LeadShare> leadShareList   = new List<LeadShare>();

        for ( Lead ld : [SELECT Id, BDM__c, OwnerId FROM Lead WHERE Id IN: ls ] )
        {
            if ( ld.BDM__c != null && ld.BDM__c <> ld.OwnerId) // add check since the BDM is sometimes the Owner!
            {
                leadMap.put( ld.Id, ld );
            }
        }

        if (leadMap.isEmpty()) return;
        
        List<Debt__share> debtList                  = new List<Debt__share>();
        List<Quote__share> quoteList                = new List<Quote__share>();
        List<Membership__share> membershipList      = new List<Membership__share>();
        List<Appraisal__share> appraisalList        = new List<Appraisal__share>();
        List<Appraisal_Order__share> apprOrderList  = new List<Appraisal_Order__share>();
        List<Property_Member__share> propertyMemList= new List<Property_Member__share>();
        List<Credit_Report__share> creditReportList = new List<Credit_Report__share>(); 

        for (Lead l : [
            SELECT Id,
            (
            SELECT Id, Lead__c, OwnerId
                FROM Debts__r
            ),
            (
            SELECT Id, Lead__c, OwnerId
                FROM Quotes__r
            ),
            (
            SELECT Id, Lead__c, OwnerId
                FROM Memberships__r
            ),
            (
            SELECT Id, Lead__c, OwnerId
                FROM Appraisals__r
            ),
            (
            SELECT Id, Lead__c, OwnerId
                FROM Property_Members__r
            )
            FROM Lead
            WHERE Id IN :leadMap.keySet()
        ])
        {
            LeadShare ldShare       = new LeadShare();
            ldShare.LeadId          = l.Id;
            ldShare.UserOrGroupId   = leadMap.get ( l.Id ).BDM__c;
            ldShare.LeadAccessLevel = 'Edit';
            ldShare.RowCause        = Schema.LeadShare.RowCause.Manual;
            leadShareList.add ( ldShare );

            for (Debt__c debt : l.Debts__r)
            {
                Debt__share db        = new Debt__share();
                db.ParentId            = debt.Id;
                db.AccessLevel         = 'Edit';
                db.RowCause            = Schema.Debt__share.RowCause.Manual;
                db.UserOrGroupId    = leadMap.get(debt.Lead__c).BDM__c;
                debtList.add(db);
            }
            for (Quote__c quote : l.Quotes__r)
            {
                Quote__share db        = new Quote__share();
                db.ParentId            = quote.Id;
                db.AccessLevel         = 'Edit';
                db.RowCause            = Schema.Quote__share.RowCause.Manual;
                db.UserOrGroupId    = leadMap.get(quote.Lead__c).BDM__c;
                quoteList.add( db );
            }
            for (Membership__c membership : l.Memberships__r)
            {
                Membership__share mb= new Membership__share();
                mb.ParentId            = membership.Id;
                mb.AccessLevel         = 'Edit';
                mb.RowCause            = Schema.Membership__share.RowCause.Manual;
                mb.UserOrGroupId    = leadMap.get(membership.Lead__c).BDM__c;
                membershipList.add(mb);
            }
            for (Appraisal__c appraisal : l.Appraisals__r)
            {
                Appraisal__share ap        = new Appraisal__share();
                ap.ParentId                = appraisal.Id;
                ap.AccessLevel             = 'Edit';
                ap.RowCause                = Schema.Appraisal__share.RowCause.Manual;
                ap.UserOrGroupId        = leadMap.get(appraisal.Lead__c).BDM__c;
                appraisalList.add( ap );
            }
            for (Property_Member__c propM : l.Property_Members__r)
            {
                Property_Member__share pm        = new Property_Member__share();
                pm.ParentId                        = propM.Id;
                pm.AccessLevel                     = 'Edit';
                pm.RowCause                        = Schema.Property_Member__share.RowCause.Manual;
                pm.UserOrGroupId                = leadMap.get(propM.Lead__c).BDM__c;
                propertyMemList.add( pm );
            }
        }
        
        for (Appraisal_Order__c apprOrder : [SELECT Id, Appraisal__c, Appraisal__r.Lead__c, OwnerId FROM Appraisal_Order__c WHERE  Appraisal__r.Lead__c =: leadMap.keySet()])
        {   
            Appraisal_Order__share apO        = new Appraisal_Order__share();
            apO.ParentId                    = apprOrder.Id;
            apO.AccessLevel                 = 'Edit';
            apO.RowCause                    = Schema.Appraisal_Order__share.RowCause.Manual;
            apO.UserOrGroupId                = leadMap.get(apprOrder.Appraisal__r.Lead__c).BDM__c;
            apprOrderList.add( apO );
        }

        for (Credit_Report__c creditReport : [SELECT Id, Property_Member__c, Property_Member__r.Lead__c, OwnerId FROM Credit_Report__c WHERE Property_Member__r.Lead__c =: leadMap.keySet()])
        {   
            Credit_Report__share crO        = new Credit_Report__share();
            crO.ParentId                    = creditReport.Id;
            crO.AccessLevel                 = 'Edit';
            crO.RowCause                    = Schema.Credit_Report__share.RowCause.Manual;
            crO.UserOrGroupId                = leadMap.get(creditReport.Property_Member__r.Lead__c).BDM__c;
            creditReportList.add( crO );
        }

        Boolean sharingFailed = false;

        try {
            insert leadShareList;
        } catch (Exception e) {
            sharingFailed = true;
            System.debug( e.getMessage());
        }

        try {
            insert debtList;
        } catch (Exception e) {
            sharingFailed = true;
            System.debug( e.getMessage());
        }

        try {
            insert quoteList;
        } catch (Exception e) {
            sharingFailed = true;
            System.debug( e.getMessage());
        }

        try {
            insert membershipList;
        } catch (Exception e) {
            sharingFailed = true;
            System.debug( e.getMessage());
        }

        try {
            insert appraisalList;
        } catch (Exception e) {
            sharingFailed = true;
            System.debug( e.getMessage());
        }

        try {
            insert apprOrderList;
        } catch (Exception e) {
            sharingFailed = true;
            System.debug( e.getMessage());
        }

        try {
            insert propertyMemList;
        } catch (Exception e) {
            sharingFailed = true;
            System.debug( e.getMessage());
        }

        try {
            insert creditReportList;
        } catch (Exception e) {
            sharingFailed = true;
            System.debug( e.getMessage());
        }

        if(sharingFailed && !System.IsBatch() && !System.IsFuture()) {
            BDMSharingCalculation batchClass = new BDMSharingCalculation();
            Id batchId = Database.executeBatch(batchClass);        
        }

    }


    /*
     * HEB-284: Platform Event for Snail Mail update to Lead
     */
    public static Boolean snailMailEventPublished = false;
    public static void snailMailPlatformEvent(List<Lead> records, Map<Id, Lead> oldRecords)
    {
        Map<Id, Lead> mailLeads = new Map<Id, Lead>();
        List<Task> newTasks = new List<Task>();
        for (Lead l : records)
        {
            if (
                l.Send_Mail_Communcation__c == true &&
                (oldRecords.get(l.Id) == null || oldRecords.get(l.Id).Send_Mail_Communcation__c == false)
            ) {
                if(
                    !Utils.allowBypassForUser() && 
                    l.Mail_Communication_Type__c == 'EST' && 
                    !l.CHIP_Qualified__c
                ) {
                    l.addError('The file must have a valid quote to send an EST letter');
                } else if(
                    !Utils.allowBypassForUser() && 
                    l.Mail_Communication_Type__c == 'MAX EST' && 
                    !l.CHIP_Max_Qualified__c
                ) {
                    l.addError('The file must have a valid CHIP Max quote to send a MAX EST letter');
                } else {
                    l.Send_Mail_Communcation__c = false; // unset this flag for subsequent communications
                    mailLeads.put(l.Id, l);
                }
            }
        }

        if (mailLeads.isEmpty()) return;

        List<MARSPlatformEventService.Request> requests = new List<MARSPlatformEventService.Request>();
        for (Lead l : mailLeads.values())
        {
            requests.add(new MARSPlatformEventService.Request(l, l.Mail_Communication_Type__c, MARSPlatformEventService.ACTION_UPDATE, MARSPlatformEventService.SNAIL_MAIL_ACTION ));
            newTasks.add(
                new Task(
                    Subject = Label.Lead_Mail_Comm_Request + ' (' + l.Mail_Communication_Type__c + ')',
                    WhoId = l.Id,
                    Status = 'Completed',
                    Priority = 'Normal',
                    Description = Label.Lead_Mail_Comm_Summary
                )
            );            
        }
        
        Boolean errorOccurred = MARSPlatformEventService.publishEvents(requests);
        LeadService.snailMailEventPublished = !(errorOccurred);
        try {
            insert newTasks;
        } catch(DmlException e) {
            System.debug(e.getMessage());
        }
    }
    
    /*
        HEB-215: When a lead is created, add a Property Member as well
    */
    public static void createMatchingPropertyMember(List<Lead> records)
    {
        if (FeatureManagement.checkPermission(Utils.CUSTOM_PERMISSION_CIRCUMVENT_DURING_DATA_LOAD)) return;
        
        List<Property_Member__c> propertyMembers = new List<Property_Member__c>();
        PropertyMembersInfoWrapper pm1FromUI = new PropertyMembersInfoWrapper();
        PropertyMembersInfoWrapper borrowerOneObject = new PropertyMembersInfoWrapper();
        PropertyMembersInfoWrapper borrowerTwoObject = new PropertyMembersInfoWrapper();
        Property_Member__c propertyMember1 = new Property_Member__c();
        Property_Member__c propertyMember2 = new Property_Member__c();
        for (Lead lead : records)
        {
            System.debug('BEFORE:::');
            if(lead.Property_Member_Info_Override__c != null){
                System.debug(lead.Property_Member_Info_Override__c);
                List<String> propertyMemberInfoList = lead.Property_Member_Info_Override__c.split('~');
                System.debug('Size of Borrowers :: ' + propertyMemberInfoList.size());
                System.debug('Split Strings :: ' + propertyMemberInfoList);

                if(propertyMemberInfoList.size() >=2 )
                {
                    System.debug('Got 2 Items ');

                    if(String.isNotBlank(propertyMemberInfoList[0])) {
                         borrowerOneObject = (PropertyMembersInfoWrapper)JSON.deserializeStrict(propertyMemberInfoList[0], PropertyMembersInfoWrapper.class);
                         System.debug('ONE :: ' + borrowerOneObject);
                    }

                    if(String.isNotBlank(propertyMemberInfoList[1])) {
                        System.debug('error :: ' + propertyMemberInfoList[1]);
                        borrowerTwoObject = (PropertyMembersInfoWrapper)JSON.deserializeStrict(propertyMemberInfoList[1], PropertyMembersInfoWrapper.class);
                        System.debug('TWO::  ' + borrowerTwoObject);
                    }
                }
            }
            System.debug('After:::');


            Property_Member__c propertyMember = new Property_Member__c();
            propertyMember.CASL_Consent_Provided_On__c    = lead.CASL_Consent_Provided_On__c;
            propertyMember.CASL_Consent__c                = lead.CASL_Consent__c;
            propertyMember.CASL_Content_Obtained_By__c    = lead.CASL_Content_Obtained_By__c;
            propertyMember.Marketing_Promotion_Opt_Out__c = lead.HasOptedOutOfEmail;
            propertyMember.Email__c                       = lead.Email;
            propertyMember.Employer_Name__c               = lead.Company;
            propertyMember.First_Name__c                  = lead.FirstName;
            propertyMember.Industry__c                    = lead.Industry;
            propertyMember.Last_Name__c                   = lead.LastName;
            propertyMember.Lives_at_Property__c           = lead.Lives_at_Property__c;
            propertyMember.Middle_Name__c                 = lead.MiddleName;
            propertyMember.On_Do_Not_Call_List__c         = lead.HasOptedOutOfFax;
            propertyMember.Phone__c                       = lead.Phone;
            propertyMember.Preferred_Name__c              = lead.Preferred_Name__c;
            propertyMember.Preferred_Spoken_Language__c   = lead.Language__c;
            propertyMember.Role__c                        = lead.Calling_for_borrower__c ? PropertyMemberService.INFLUENCER_ROLE : PropertyMemberService.BORROWER_ROLE;
            propertyMember.Salutation__c                  = lead.Salutation;
            propertyMember.Lead__c                        = lead.Id;
            if(lead.CreatedFromLeadUI__c == true){
                propertyMember.Role__c = PropertyMemberService.INFLUENCER_ROLE;

                propertyMember.Primary_City__c = lead.City;
                propertyMember.Primary_Country__c = lead.Country;
                propertyMember.Primary_Postal_Code__c = lead.PostalCode;
                propertyMember.Primary_Province__c = lead.StateCode;
                propertyMember.Primary_Street__c = lead.Street;

                
            }
            if(borrowerOneObject != null) {
                //Logic need to add here
                if(borrowerOneObject.isPrimaryContact != null && borrowerOneObject.isPrimaryContact) 
                {
                    propertyMember.Date_of_Birth__c = String.isNotBlank(borrowerOneObject.dateOfBirth) ? Date.valueOf(borrowerOneObject.dateOfBirth): null;
                    if(borrowerOneObject != null && borrowerOneObject.age != '') {
                        propertyMember.Age__c  = borrowerOneObject.age != null ? double.valueOf(borrowerOneObject.age) : null;
                }
                propertyMember.Gender__c = borrowerOneObject.gender;
                propertyMember.Marital_Status__c = borrowerOneObject.maritalStatus;
                propertyMember.Primary_City__c = borrowerOneObject.primaryCity;
                propertyMember.Primary_Country__c = borrowerOneObject.primaryCountry;
                propertyMember.Primary_Postal_Code__c = borrowerOneObject.primaryPostalCode;
                propertyMember.Primary_Province__c = borrowerOneObject.primaryProvince;
                propertyMember.Primary_Street__c = borrowerOneObject.primaryStreet;
                propertyMember.Use_For_Quote__c = true;
                propertyMember.Role__c = PropertyMemberService.BORROWER_ROLE;
                propertyMember.CreatedFromLeadUI__c = true;
                
                if(borrowerOneObject.isPrimaryBorrower =='true'){
                        propertyMember.Is_Primary_Borrower__c = true;
                    }
                }
                else if(borrowerOneObject.isPrimaryContact != null && 
                        !borrowerOneObject.isPrimaryContact && borrowerOneObject.firstName != null 
                        && borrowerOneObject.firstName != '' && borrowerOneObject.lastName != null 
                        && borrowerOneObject.lastName != '')
                {
                    propertyMember.Role__c = PropertyMemberService.INFLUENCER_ROLE;
                    propertyMember.Use_For_Quote__c = false;
                    propertyMember.Primary_City__c = lead.City;
                    propertyMember.Primary_Country__c = lead.Country;
                    propertyMember.Primary_Postal_Code__c = lead.PostalCode;
                    propertyMember.Primary_Province__c = lead.StateCode;
                    propertyMember.Primary_Street__c = lead.Street;
                    propertyMember.CreatedFromLeadUI__c = true;

                    propertyMember1.Salutation__c = borrowerOneObject.salutation;
                    propertyMember1.First_Name__c = borrowerOneObject.firstName;
                    propertyMember1.Last_Name__c = borrowerOneObject.lastName;
                    propertyMember1.Date_of_Birth__c = String.isNotBlank(borrowerOneObject.dateOfBirth) ? Date.valueOf(borrowerOneObject.dateOfBirth): null;
                    if(borrowerOneObject != null && borrowerOneObject.age != '') {
                        propertyMember1.Age__c  = borrowerOneObject.age != null ? double.valueOf(borrowerOneObject.age) : null;
                    }
                    propertyMember1.Gender__c = borrowerOneObject.gender;
                    propertyMember1.Marital_Status__c = borrowerOneObject.maritalStatus;
                    propertyMember1.Primary_City__c = borrowerOneObject.primaryCity;
                    propertyMember1.Primary_Country__c = borrowerOneObject.primaryCountry;
                    propertyMember1.Primary_Postal_Code__c = borrowerOneObject.primaryPostalCode;
                    propertyMember1.Primary_Province__c = borrowerOneObject.primaryProvince;
                    propertyMember1.Primary_Street__c = borrowerOneObject.primaryStreet;
                    propertyMember1.Use_For_Quote__c = true;
                    propertyMember1.Role__c = PropertyMemberService.BORROWER_ROLE;
                    propertyMember1.CreatedFromLeadUI__c = true;
                    if(borrowerOneObject.isPrimaryBorrower == 'true'){
                        propertyMember1.Is_Primary_Borrower__c = true;
                    }
                    propertyMember1.Lead__c = lead.Id;
                }
               
            }
            propertyMembers.add(propertyMember);
            
            if(propertyMember1!=null && propertyMember1.First_Name__c != null && propertyMember1.First_Name__c != '' && propertyMember1.Last_Name__c!=null && propertyMember1.Last_Name__c!=''){
                propertyMembers.add(propertyMember1);
            }
            
            if(borrowerTwoObject != null && 
               borrowerTwoObject.firstName != null 
               && borrowerTwoObject.firstName != '' 
               && borrowerTwoObject.lastName != null 
               && borrowerTwoObject.lastName != '') 
            {
                //Logic need to add here
                propertyMember2.Salutation__c = borrowerTwoObject.salutation;
                propertyMember2.First_Name__c = borrowerTwoObject.firstName;
                propertyMember2.Last_Name__c = borrowerTwoObject.lastName;
                propertyMember2.Date_of_Birth__c = String.isNotBlank(borrowerTwoObject.dateOfBirth) ? Date.valueOf(borrowerTwoObject.dateOfBirth): null;
                if(borrowerTwoObject != null && borrowerTwoObject.age != '') {
                    propertyMember2.Age__c  = borrowerTwoObject.age != null ? double.valueOf(borrowerTwoObject.age) : null;
                }
                propertyMember2.Gender__c = borrowerTwoObject.gender;
                propertyMember2.Marital_Status__c = borrowerTwoObject.maritalStatus;
                propertyMember2.Primary_City__c = borrowerTwoObject.primaryCity;
                propertyMember2.Primary_Country__c = borrowerTwoObject.primaryCountry;
                propertyMember2.Primary_Postal_Code__c = borrowerTwoObject.primaryPostalCode;
                propertyMember2.Primary_Province__c = borrowerTwoObject.primaryProvince;
                propertyMember2.Primary_Street__c = borrowerTwoObject.primaryStreet;
                propertyMember2.Role__c = PropertyMemberService.BORROWER_ROLE;
                propertyMember2.Use_For_Quote__c = true;
                propertyMember2.CreatedFromLeadUI__c = true;
                propertyMember2.Lead__c = lead.Id;
                propertyMembers.add(propertyMember2);
            }
           
        }
        try{
            if(propertyMembers != null && propertyMembers.size() > 0){
                System.debug('Before Insert :: Property Members');
                insert propertyMembers;
                System.debug('After Insert :: Property Members');
                
                if(propertyMembers != null && propertyMembers.size() >=2 ){
                    List<Property_Member_Relationship__c> toSaveList = 
                                SetAndGetPropertyMemberRelationShip(propertyMembers, borrowerOneObject, borrowerTwoObject);
                    if(toSaveList != null && toSaveList.size() > 0){
                        System.debug('Before Insert :: Property relationship');
                        insert toSaveList;
                        System.debug('After Insert :: Property relationship');
                    }
                    else {
                        System.debug('Empty');

                    }
                }
            }
        }
        catch(DmlException e){
            for (Lead l : records)
            {
                l.addError('Error [Property Member creation]: ' + e.getMessage());
            }
        }
    }

    public static List<Property_Member_Relationship__c> SetAndGetPropertyMemberRelationShip(List<Property_Member__c> insertedRecords ,PropertyMembersInfoWrapper one, PropertyMembersInfoWrapper two) {
            List<Property_Member_Relationship__c> pmRelationShipCollection = new List<Property_Member_Relationship__c>();
            Property_Member__c primaryPropertyMember = new Property_Member__c();
            Property_Member__c secondayPropertyMember = new Property_Member__c();
            System.debug(insertedRecords);
            
            if(insertedRecords.size() == 3){
                primaryPropertyMember =  insertedRecords[1];
                secondayPropertyMember = insertedRecords[2];
            }
            else if(insertedRecords.size() > 0 && insertedRecords.size() < 3) {
                primaryPropertyMember =  insertedRecords[0];
                secondayPropertyMember = insertedRecords[1];
            }
            
            System.debug('Primary'+ primaryPropertyMember );
            System.debug('Secondary' + secondayPropertyMember);

            if(primaryPropertyMember != null  && secondayPropertyMember != null
                        && !String.isBlank(primaryPropertyMember.First_Name__c) 
                        && !String.isBlank(primaryPropertyMember.Last_Name__c)
                        && primaryPropertyMember.Role__c != 'Influencer'
                        && !String.isBlank(secondayPropertyMember.First_Name__c) 
                        && !String.isBlank(secondayPropertyMember.Last_Name__c))
            {
                System.debug('Setting Pro Relationship');
                
                Property_Member_Relationship__c propertyMemberrRelationShip = new Property_Member_Relationship__c();

                propertyMemberrRelationShip.Property_Member__c = secondayPropertyMember.Id;
                propertyMemberrRelationShip.Relationship_Category__c = two.controlling;
                propertyMemberrRelationShip.Relationship_Type__c = two.dependent;
                propertyMemberrRelationShip.Relates_to__c = primaryPropertyMember.Id;
                if(propertyMemberrRelationShip.Relationship_Category__c!='' && propertyMemberrRelationShip.Relationship_Type__c != '' ){
                    pmRelationShipCollection.add(propertyMemberrRelationShip);
                }
                

                propertyMemberrRelationShip = new Property_Member_Relationship__c();
                propertyMemberrRelationShip.Property_Member__c = primaryPropertyMember.Id;
                propertyMemberrRelationShip.Relationship_Category__c = one.controlling;
                propertyMemberrRelationShip.Relationship_Type__c = one.dependent;
                propertyMemberrRelationShip.Relates_to__c = secondayPropertyMember.Id;
                if(propertyMemberrRelationShip.Relationship_Category__c!='' && propertyMemberrRelationShip.Relationship_Type__c != '' ){
                pmRelationShipCollection.add(propertyMemberrRelationShip);
                } 
            }
            return pmRelationShipCollection;
    } 
    public class PropertyMembersInfoWrapper 
     {
        public Boolean isPrimaryContact {get; set;}
        public string salutation {get; set;}
        public string firstName {get; set;} 
        public string lastName {get; set;}
        public string age {get; set;}
        public string gender {get; set;}
        public string dateOfBirth {get; set;}
        public string maritalStatus {get; set;}
        public string primaryCity {get; set;}
        public string primaryCountry {get; set;}
        public string primaryPostalCode {get; set;}
        public string primaryProvince {get; set;}
        public string primaryStreet {get; set;}
        public string isMailingAddressSameAsProperty {get; set;}
        public string isPrimaryBorrower {get; set;}
        public string dependent {get; set;}
        public string controlling {get; set;}
    }

    public void checkRequote(List<Lead> records, Map<Id, Lead> oldRecords)
    {
        // do not run for Integration user; MARS will update the flag directly when all related records complete
        if(Utils.isIntegrationUser())
            return;

        Set<String> fieldsToCheck = Utils.getFieldSetFields(Schema.SObjectType.Lead.fieldSets.Influences_Quote.getFields());
        List<Lead> ls = (List<Lead>) Utils.getChangedObjects(records, oldRecords, fieldsToCheck);
        

        for (Lead l : ls)
        {
            l.Quote_Parameters_Updated__c = true;
        }
    }
    
    public void mergeRequote(List<Lead> records)
    {
        Set<Id> survivingRecordIDs = new Set<Id>();
        for (Lead l : records)
        {
            if (l.MasterRecordId != null)
            {
                survivingRecordIDs.add(l.MasterRecordId);
            }
        }
        
        setRequote(survivingRecordIDs);
    }
    
    @future(callout=true)
    private static void setRequote(Set<Id> leadIDs)
    {
        // do not run for Integration user; MARS will update the flag directly when all related records complete
        if(Utils.isIntegrationUser())
            return;

        List<Lead> ls = [
            SELECT Id, Quote_Parameters_Updated__c
            FROM Lead
            WHERE Id IN :leadIDs
        ];
        
        for (Lead l : ls)
        {
            l.Quote_Parameters_Updated__c = true;
        }
        
        update ls;
    }

    /*
    * HEB-349 Update the Active Quote when the Product type changes
    */
    public void updateActiveQuote(List<Lead> records, Map<Id, Lead> oldRecords)
    {
        Set<String> fieldsToCheck = new Set<String>{'Product_Type__c'};
        List<Lead> ls = (List<Lead>) Utils.getChangedObjects(records, oldRecords, fieldsToCheck);
        Map<Id, Lead> newRecords = new MAp<Id, Lead>();

        for ( Lead ld : ls )
        {
            newRecords.put( ld.Id, ld );
        }

        if (newRecords.isEmpty()) return;

        Map<Id, Id> leadActiveQuoteMap = new Map<Id, Id>();
        for ( Quote__c q : [
            SELECT Id, Selected__c, Product_Type__c, Lead__c
            FROM Quote__c 
            WHERE Active_Quote__c = true 
            AND Lead__c = :ls
        ])
        {
            Lead newLead = newRecords.get( q.Lead__c );
            if ( newLead.Product_Type__c == q.Product_Type__c )
            {
                leadActiveQuoteMap.put( q.Lead__c, q.Id);
            }
        }
        for ( Lead l : ls )
        {
            l.Active_Quote__c = leadActiveQuoteMap.get(l.Id);
        }
    }

    /*
    * HEB-349 Update the Selected Quote when the Product type changes
    */
    public void updateSelectedQuote(List<Lead> records, Map<Id, Lead> oldRecords)
    {
        Set<String> fieldsToCheck = new Set<String>{'Product_Type__c'};
        List<Lead> ls = (List<Lead>) Utils.getChangedObjects(records, oldRecords, fieldsToCheck);
        Map<Id, Lead> newRecords = new MAp<Id, Lead>();

        for ( Lead ld : ls )
        {
            newRecords.put( ld.Id, ld );
        }

        if (newRecords.isEmpty()) return;

        List<Quote__c> quoteUpdtList = new List<Quote__c>();
        for ( Quote__c q : [
            SELECT Id, Selected__c, Product_Type__c, Lead__c
            FROM Quote__c 
            WHERE Active_Quote__c = true 
            AND Lead__c = :ls
        ])
        {
            Lead newLead = newRecords.get( q.Lead__c );
            if ( newLead.Product_Type__c == q.Product_Type__c && !q.Selected__c)
            {
                q.Selected__c = true;
                quoteUpdtList.add( q );
            }
            
               // The selected gets unchecked in the Quote trigger oneSelectedQuote
            }

        try {
            if ( ! quoteUpdtList.isEmpty()) update quoteUpdtList;
        } catch (Exception e)  {
            system.debug(LoggingLevel.ERROR, e.getMessage());
        }
    }
    
    /**
       HEB-288: When a lead is assigned, track the updated count.
     */
    public void addNewLeadAssignment(List<Lead> records, Map<Id, Lead> oldRecords)
    {
        // Find all leads with an updated owner.
        Set<Id> userIds = new Set<Id>();
        for (Lead l : (List<Lead>) Utils.getChangedObjects(records, oldRecords, new Set<String>{'OwnerId'}))
        {
            userIds.add(l.OwnerId);
        }
        
        // Find all updated owners who are a specialist.
        Map<Id, Specialist__c> spls = new Map<Id, Specialist__c>([
            SELECT Id
            FROM Specialist__c
            WHERE User__c IN :userIds
        ]);
        
        // Increase lead assigned count.
        LeadAssignmentService.incrementAssignmentCount(spls.keySet());
    }

    /** HEB-367 When lead details are updated a new quote is requested */
    public void updateQuote(List<Lead> records, Map<Id, Lead> oldRecords)
    {
        if (System.isBatch()) return;
        
        if (FeatureManagement.checkPermission(Utils.CUSTOM_PERMISSION_CIRCUMVENT_DURING_DATA_LOAD)) return;
        
        //Return early if this is a mass update
        if (records.size() > 1) return;
        
        // Prevents future recursion
        if (system.isFuture()) return;

        //Check if quote paramters are updated
        Lead updatedLead = records[0];
        
        // Skip quoting if converted
        if (updatedLead.IsConverted == true && oldRecords.get(updatedLead.Id).IsConverted == false) return;

        // If updated get a new quote 
        if (updatedLead.Quote_Parameters_Updated__c
            && !Test.isRunningTest()
            && !inhibitQuoteCallout
           )
        {
            QuoteRequestValidationController.getQuoteForTrigger(updatedLead.Id);
        }
    }

    /*
     * HEB-14: Create Campaign Influence record for converted Lead's Opportunity
     */
    public void createCampaignInfluenceRecords(List<Lead> records, Map<Id, Lead> oldRecords)
    {
        Map<Id, Lead> oppLeadMap = new Map<Id, Lead>();
        for (Lead l : records) 
        {
            if (l.IsConverted == true && oldRecords.get(l.Id).IsConverted == false) 
            {
                oppLeadMap.put(l.ConvertedOpportunityId, l);
            }
        }
        System.debug('createCampaignInfluenceRecords: oppLeadMap = ' + oppLeadMap);
        
        // if no converted leads, no action
        if (oppLeadMap.isEmpty()) return;
        
        /*
         * Get relevant Campaigns to the converted lead(s)
         */
        Map<Id, List<CampaignMember>> leadCampaignMembers = new Map<Id, List<CampaignMember>>();
        for (CampaignMember cm : [
            SELECT Id, CampaignId, LeadId
            FROM CampaignMember
            WHERE LeadId IN : oppLeadMap.values()
        ]) {
            List<CampaignMember> tmpList = leadCampaignMembers.get(cm.LeadId) <> null ? leadCampaignMembers.get(cm.LeadId) : new List<CampaignMember>();
            tmpList.add(cm);
            leadCampaignMembers.put(cm.LeadId, tmpList);
        }
        System.debug('createCampaignInfluenceRecords: leadCampaignMembers = ' + leadCampaignMembers);
    
        // if no campaign members, no action
        if (leadCampaignMembers.isEmpty()) return;

        List<CampaignInfluenceModel> influenceModelList = [
            SELECT Id
            FROM CampaignInfluenceModel
            WHERE IsDefaultModel = true
        ];
        
        // if no influence models, no action.
        if (influenceModelList.isEmpty()) return;
        
        List<CampaignInfluence> influenceList = new List<CampaignInfluence>();
        for (Id opportunityId : oppLeadMap.keySet())
        {
            for (CampaignMember cm : leadCampaignMembers.get(oppLeadMap.get(opportunityId).Id))
            {
                Double influenceShare = 100 / leadCampaignMembers.get(oppLeadMap.get(opportunityId).Id).size();
                influenceList.add(new CampaignInfluence(
                    CampaignId    = cm.CampaignId,
                    ContactId     = oppLeadMap.get(opportunityId).ConvertedContactId,  
                    Influence     = influenceShare,
                    ModelId       = influenceModelList[0].Id,
                    OpportunityId = opportunityId
                ));
            }
        }
        System.debug('createCampaignInfluenceRecords: influenceList = ' + influenceList);

        try {
            insert influenceList;
            System.debug('createCampaignInfluenceRecords: influenceList = ' + influenceList);
        } catch(DmlException e) {
            System.debug(e.getMessage());
        }
    }
    
    /**
     * HEB-201: Mark closed lost files are no longer checked for duplicates.
     */
    public void deactivateDuplicateCheck(List<Lead> records, Map<Id, Lead> oldRecords)
    {
        Set<String> fieldsToCheck = new Set<String>{'Status'};
        for (Lead l : (List<Lead>) Utils.getChangedObjects(records, oldRecords, fieldsToCheck))
        {
            if (l.Status == LEAD_STATUS_CLOSEDLOST)
            {
                l.Check_for_Duplicate__c = Utils.NEGATIVE;
            }
        }
    }

    /*
     * Map the contact recordtype to the territory channel type.
     */
    public static String getContactPC(Id recordTypeID)
    {
        Map<String, ID> rtIDs = Utils.getRecordTypeIdsBySObjectType(Contact.sObjectType);
        Map<ID, String> RTs = Utils.invertMapping(rtIDs);
        
        String RT = RTs.get(recordTypeID);
        return contactPC.get(RT);
    }
    
    /*
     * HEB-223: File Validation prior to Commitment Letter
     * - ensure the Lead and Credit Report are all in good standing before finalizing commitment letter.
     */
    public void fileValidationPriorToCommitmentLetter(List<Lead> records, Map<Id, Lead> oldRecords)
    {
        List<Lead> validateFiles = new List<Lead>();
        for (Lead ld : records)
        {
            if (ld.Commitment_Letter_Decision_Date__c == null
                && (ld.Commitment_Letter_Decision__c <> null
                || (
                    ld.Commitment_Letter_Decision__c == null
                    && oldRecords.get(ld.Id).Commitment_Letter_Decision__c <> null
               )
                || ld.Commitment_Letter_Validation_Message__c <> null
               )
               )
            {
                validateFiles.add(ld);
            }
        }
        
        if (validateFiles.isEmpty()) return;
        
        //if (!PartnerEstimateLetterService.generateCommitmentLetterEventPublished)
        PartnerEstimateLetterService.validateForCommitmentLetter(validateFiles, PartnerEstimateLetterService.Mode.Record_State);
            }
                
    /*
     * HEB-445: New service method for retrieving Lead details, to be leveraged in Appraisal services
     */    
    public static Lead retrieveLeadDetails(Id leadId)
    {
        try {
            return [
                SELECT Id
                , File_Number__c
                , File_Type__c
                , Channel__c
                , Partner_Referrer__r.FirstName
                , Partner_Referrer__r.LastName
                , Partner_Referrer__r.Email
                , Annual_Property_Taxes__c
                , Condo_Fees_Current__c
                , Condo_Fees_Owing__c
                , Fire_Insurance_Premium__c
                , Fire_Insurance_in_place_for_12_Months__c
                , Monthly_Condo_Fees__c
                , Property_Value_for_Quote__c
                , Property_Taxes_Current__c
                , Property_Tax_Owing__c
                , Language__c
                , Status
                , Property__c
                , Appraisal_Option__c
                , OwnerId
                , BDM__c 
                , Product_Quote_Set__c
                , Product_Quote_Set__r.External_ID__c
                , Product_Quote_Set__r.Effective_Date__c
                , Product_Rate_Set__c
                , Product_Rate_Set__r.External_ID__c
                , Product_Rate_Set__r.Effective_Date__c                
                , (
                    SELECT Id
                    , First_Name__c
                    , Last_Name__c
                    , Preferred_Name__c
                    , Date_of_Birth__c
                    , Age__c
                    , Phone__c
                    , Alternate_Phone_Number__c
                    , Email__c
                    , Credit_Score__c
                    , Is_Primary_Borrower__c
                    , Monthly_OAS_Income__c, Monthly_CPP_Income__c, Monthly_Pension_Income__c, Monthly_Employment_Income__c
                    , Monthly_Rental_Income__c, Monthly_Investment_Income__c, Monthly_Support_Income_Assets__c
                    FROM Property_Members__r
                    WHERE Role__c INCLUDES (:PropertyMemberService.BORROWER_ROLE)
                     AND Use_For_Quote__c = true
                    ORDER BY Age__c LIMIT 2
                )
                , (
                    SELECT Id
                    , Quote_Amount__c
                    , EOT__c
                    , Property_Type_Rating__c
                    , Location_Code__c
                    FROM Quotes__r
                    WHERE Selected__c = TRUE
                )
                , (
                    SELECT Id
                    , Amount__c, Secured__c
                    FROM Debts__r
                )
                FROM Lead
                WHERE Id = :leadId
                AND IsConverted = FALSE
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
        } catch(Exception e) {
            return null;
        }
    }

    /*
     * Assumption: Leads are never closed lost in bulk. 
     * If this is not the case, then the appraisal cancellations will need to be handled in batch.
     */
    public void cancelAppraisals(List<Lead> records, Map<Id, Lead> oldRecords)
    {
        Set<Id> closedLostLeads = new Set<Id>();
        
        for (Lead l : records)
        {
            // Lead is now closed lost.
            if (l.Status == LOST_LEAD && l.Status <> oldRecords.get(l.Id).Status)
            {
                closedLostLeads.add(l.Id);
            }
        }
        
        List<Appraisal_Order__c> aos = [
            SELECT Id
            , Cancellation_Reason__c
            , Reference_ID__c
            FROM Appraisal_Order__c
            WHERE Appraisal__r.Lead__c IN :closedLostLeads
            AND Cancellation_Reason__c = NULL
        ];
        
        for (Appraisal_Order__c ao : aos)
        {
            ao.Cancellation_Reason__c = AppraisalCancelOrderService.CANCEL_REASON_FILE_CLOSED_LOST;
        }
        update aos;

        for (Appraisal_Order__c ao : aos)
        {
            if (ao.Reference_ID__c != null) // Send cancellation to MARS only if previously sent.
            {
                AppraisalOrderController.cancelAppraisalOrderPostClosedLost(ao.Id);
            }
        }
    }


    /*
     * HEB-405: File Valdiation prior to Launch to MARS
     * HEB-443: File Validation moved from Opportunity to Lead
     * - ensure the Lead and related records (Property, Property Member, Quote) are all in good standing before trying to integrate w/ MARS
     */
    public void fileValidationPriorToMARS(List<Lead> records, Map<Id, Lead> oldRecords)
    {
        Map<Id, Lead> marsFiles = new Map<Id, Lead>();

        // get relevant records; return if none
        for (Lead l : records) {
            if (l.Status == LEAD_STATUS_PREAPPLICATION || l.Missing_MARS_Validation_Message__c <> null || l.Commitment_Letter_Validation_Message__c <> null) {
                marsFiles.put(l.Id, l);
            }
        }
        if (marsFiles.isEmpty())
            return;
 
        Set<String> leadFields                          = Utils.getFieldSetFields(Schema.SObjectType.Lead.fieldSets.File_Validation.getFields());
        Set<String> leadConsent                           = Utils.getFieldSetFields(Schema.SObjectType.Lead.fieldSets.File_Validation_Consent.getFields());
        Set<String> propertyFields                      = Utils.getFieldSetFields(Schema.SObjectType.Property__c.fieldSets.File_Validation.getFields());
        Set<String> propertyMemberFields                = Utils.getFieldSetFields(Schema.SObjectType.Property_Member__c.fieldSets.File_Validation_Borrowers.getFields());
        Set<String> propertyMemberConsent               = Utils.getFieldSetFields(Schema.SObjectType.Property_Member__c.fieldSets.File_Validation_Consent.getFields());
        Set<String> propertyMemberAMLOccupationFields   = Utils.getFieldSetFields(Schema.SObjectType.Property_Member__c.fieldSets.File_Validation_AML_Occupation.getFields());
        
        Set<String> propertyMemberAMLUnempOtherFields   = Utils.getFieldSetFields(Schema.SObjectType.Property_Member__c.fieldSets.File_Validation_AML_Unemployed_Other.getFields());
        Set<String> propertyMemberAMLUnempHomemakerFields = Utils.getFieldSetFields(Schema.SObjectType.Property_Member__c.fieldSets.File_Validation_AML_Unemployed_Homemaker.getFields());
        Set<String> propertyMemberAMLUnempNoPrevFields  = Utils.getFieldSetFields(Schema.SObjectType.Property_Member__c.fieldSets.File_Validation_AML_Unemployed_No_Prev.getFields());
        Set<String> propertyMemberAMLRetiredOtherFields = Utils.getFieldSetFields(Schema.SObjectType.Property_Member__c.fieldSets.File_Validation_AML_Retired_Other.getFields());
        Set<String> propertyMemberAMLAllOtherFields     = Utils.getFieldSetFields(Schema.SObjectType.Property_Member__c.fieldSets.File_Validation_AML_All_Other.getFields());
        Set<String> propertyMemberAMLFields             = Utils.getFieldSetFields(Schema.SObjectType.Property_Member__c.fieldSets.File_Validation_AML.getFields());

        Map<String, Schema.SObjectField> leadFieldMap           = Utils.getFieldMap('Lead');
        Map<String, Schema.SObjectField> propertyFieldMap       = Utils.getFieldMap('Property__c');
        Map<String, Schema.SObjectField> propertyMemberFieldMap = Utils.getFieldMap('Property_Member__c');
        
        String leadIds = String.join((Iterable<String>)marsFiles.keySet(), '\', \'');
        String propertyFieldsQuery = '';
        for (String s : propertyFields) {
            propertyFieldsQuery += (propertyFieldsQuery == '') ? 'Property__r.' + s : ', ' + 'Property__r.' + s;
        }

        String propertyMemberFieldsQuery = 'Name__c,Email__c,Active_POA__c,Role__c,Use_For_Quote__c';
        for (String s : propertyMemberFields) {
            propertyMemberFieldsQuery += (propertyMemberFieldsQuery == '') ? s : ', ' + s;
        }
        for (String s : propertyMemberConsent) {
            propertyMemberFieldsQuery += (propertyMemberFieldsQuery == '') ? s : ', ' + s;
        }
        for (String s : propertyMemberAMLOccupationFields) {
            propertyMemberFieldsQuery += (propertyMemberFieldsQuery == '') ? s : ', ' + s;
        }

        String leadFieldString = 'Id, Property__c, Active_Quote__r.Is_Eligible__c, Campaign_Member_Count__c, RecordType.DeveloperName, Blanket_Mortgage_File__c, Credit_Assessment_Required__c';
        if (!propertyFields.contains('Property_Type__c'))
            leadFieldString += ', Property__r.Property_Type__c ';
        if (!propertyFields.contains('Fixed_To_Ground__c'))
            leadFieldString += ', Property__r.Fixed_To_Ground__c ';
        if (!propertyFields.contains('Valid_FSA__c'))
            leadFieldString += ', Property__r.Valid_FSA__c ';
        
        String eventQuery = ' (SELECT Id FROM Events WHERE Type_of_Meeting__c IN (\'' + EventService.INITIAL_CONTACT_MEETING + '\', \'' + EventService.INITIAL_CONTACT_FOLLOWUP + '\') AND Dispositioned__c = true) ';     
        /* 
         * Let's grab the relevant records - we will grab all, rather than piecemeal, to return as robust an error to the end user as possible
         */
        String leadQuery = 'SELECT ' + leadFieldString + ', ' + propertyFieldsQuery + ', (SELECT Id, On_Title__c, ' + propertyMemberFieldsQuery + ' FROM Property_Members__r ), ' + eventQuery + ' FROM Lead WHERE Id IN (\'' + leadIds + '\')';
        System.debug('leadQuery = ' + leadQuery);
        Map<Id, Lead> leadRelatedMap = new Map<Id, Lead>();
        for (Lead l : Database.query(leadQuery)) {
             leadRelatedMap.put(l.Id, l);
        }
        
        for (Lead l : marsFiles.values()) {
            system.debug(leadRelatedMap.get(l.Id));
            List<String> leadErrors = new List<String>();
            
            List<String> missingLeadFields = Utils.missingFields(leadFields, leadFieldMap, l);
            if (!missingLeadFields.isEmpty())
                leadErrors.add(Label.Error_Opportunity_File_Field + ': ' + String.join(missingLeadFields, ', '));
                
            if(l.Email <> null) {
                List<String> missingLeadConsentFields = Utils.missingFields(leadConsent, leadFieldMap, l);
                if (!missingLeadConsentFields.isEmpty())
                    leadErrors.add(Label.Error_Opportunity_File_Field + ': ' + String.join(missingLeadConsentFields, ', '));
            }
            
            // check the key fields on the Property record are complete
                List<String> missingPropertyFields = new List<String>();
                if(leadRelatedMap.get(l.Id).Property__c == null) {
                    leadErrors.add(Label.Error_File_No_Property);
                } else {
                    for (String s : propertyFields) {
                        if (leadRelatedMap.get(l.Id).Property__r.get(s) == null || leadRelatedMap.get(l.Id).Property__r.get(s) == '') {
                            missingPropertyFields.add(propertyFieldMap.get(s).getDescribe().getLabel());
                        }
                    }
    
                    if (
                        leadRelatedMap.get(l.Id).Property__r.Property_Type__c == 'Mobile Home' &&
                        leadRelatedMap.get(l.Id).Property__r.Fixed_To_Ground__c != Utils.AFFIRMATIVE
                    ) {
                        leadErrors.add(Label.Error_File_Validation_Mobile_Home);
                    }
    
                    if (!leadRelatedMap.get(l.Id).Property__r.Valid_FSA__c) {
                        leadErrors.add(Label.Error_FileValidation_PropertyFSA);
                    }
                
                }

                if (!missingPropertyFields.isEmpty())
                    leadErrors.add(Label.Error_Property_Field + ': ' + String.join(missingPropertyFields, ', '));
            // end Property check 

            // Start Property Member check
                if (leadRelatedMap.get(l.Id).Property_Members__r.size() == 0) {
                    leadErrors.add(Label.Error_File_Validation_Borrower_Exists);
                }

                Boolean onTitleMissing = true;
                Boolean activePOA = false;
                Boolean activeGuarantor = false;
                // check that the key fields for the Borrower are complete, along with the AML fields
                for (Property_Member__c pm : leadRelatedMap.get(l.Id).Property_Members__r) {
                    if(pm.Role__c <> null && pm.Role__c.contains(PropertyMemberService.POA_ROLE))
                        activePOA = true;
                        if(pm.Role__c <> null && pm.Role__c.contains(PropertyMemberService.GUARANTOR_ROLE))
                        activeGuarantor = true;

                    if(pm.Use_For_Quote__c) {

                        List<String> missingPropertyMemberFields = Utils.missingFields(propertyMemberFields, propertyMemberFieldMap, pm);
                        if (!missingPropertyFields.isEmpty())
                            leadErrors.add(Label.Error_Property_Member_Borrower_Field + ': ' + String.join(missingPropertyMemberFields, ', '));

                        if(pm.Email__c <> null) {
                            List<String> missingPropertyMemberConsentFields = Utils.missingFields(propertyMemberConsent, propertyMemberFieldMap, pm);
                            if (!missingPropertyMemberConsentFields.isEmpty())
                                leadErrors.add(Label.Error_Property_Member_Borrower_Field + ' (' + pm.Name__c + '): ' + String.join(missingPropertyMemberConsentFields, ', '));
                        }


                        if ( pm.Current_Occupation__c == PropertyMemberService.OCCUPATION_OTHER && String.isEmpty(pm.Current_Occupation_Other__c) )
                        {
                            leadErrors.add(Label.Error_Property_Member_AML_OtherOccupation + ' (' + pm.Name__c + '): ' + 'Current Occupation Other');
                        }
                        if ( pm.Previous_Occupation__c == PropertyMemberService.OCCUPATION_OTHER &&  String.isEmpty(pm.Previous_Occupation_Other__c))
                        {
                            leadErrors.add(Label.Error_Property_Member_AML_OtherOccupation + ' (' + pm.Name__c + '): ' + 'Previous Occupation Other');
                        }

                        // HEB- 654 - Occupation validation for AML
                        if( pm.Age__c < 70 ) 
                        {
                            if( pm.Current_Occupation__c == PropertyMemberService.OCCUPATION_UNEMPLOYED ){

                                if ( pm.Previous_Occupation__c == PropertyMemberService.OCCUPATION_HOMEMAKER ) {
                                    List<String> missingPropertyMemberAMLOccFields = Utils.missingFields(propertyMemberAMLUnempHomemakerFields, propertyMemberFieldMap, pm);
                                    if (!missingPropertyMemberAMLOccFields.isEmpty())
                                        leadErrors.add(Label.Error_Property_Member_AML_Field + ' (' + pm.Name__c + '): ' + String.join(missingPropertyMemberAMLOccFields, ', '));
                                
                                } else {

                                    List<String> missingPropertyMemberAMLOccFields = Utils.missingFields(propertyMemberAMLUnempOtherFields, propertyMemberFieldMap, pm);
                                    if (!missingPropertyMemberAMLOccFields.isEmpty())
                                        leadErrors.add(Label.Error_Property_Member_AML_Field + ' (' + pm.Name__c + '): ' + String.join(missingPropertyMemberAMLOccFields, ', '));
                                }

                            } else if ( pm.Current_Occupation__c == PropertyMemberService.OCCUPATION_RETIRED ){

                                if ( pm.Previous_Occupation__c == PropertyMemberService.OCCUPATION_HOMEMAKER ) {

                                    List<String> missingPropertyMemberAMLOccFields = Utils.missingFields(propertyMemberAMLUnempHomemakerFields, propertyMemberFieldMap, pm);
                                    if (!missingPropertyMemberAMLOccFields.isEmpty())
                                        leadErrors.add(Label.Error_Property_Member_AML_Field + ' (' + pm.Name__c + '): ' + String.join(missingPropertyMemberAMLOccFields, ', '));
                                
                                } else {

                                    List<String> missingPropertyMemberAMLOccFields = Utils.missingFields(propertyMemberAMLRetiredOtherFields, propertyMemberFieldMap, pm);
                                    if (!missingPropertyMemberAMLOccFields.isEmpty())
                                        leadErrors.add(Label.Error_Property_Member_AML_Field + ' (' + pm.Name__c + '): ' + String.join(missingPropertyMemberAMLOccFields, ', '));
                                }

                            } else if ( pm.Current_Occupation__c != PropertyMemberService.OCCUPATION_NEVER_EMPLOYED && pm.Current_Occupation__c != PropertyMemberService.OCCUPATION_HOMEMAKER ) {

                                List<String> missingPropertyMemberAMLOccFields = Utils.missingFields( propertyMemberAMLAllOtherFields, propertyMemberFieldMap, pm);
                                    if (!missingPropertyMemberAMLOccFields.isEmpty())
                                        leadErrors.add(Label.Error_Property_Member_AML_Field + ' (' + pm.Name__c + '): ' + String.join(missingPropertyMemberAMLOccFields, ', '));
                            } else {

                                List<String> missingPropertyMemberAMLFields = Utils.missingFields(propertyMemberAMLFields, propertyMemberFieldMap, pm);
                                if (!missingPropertyMemberAMLFields.isEmpty())
                                    leadErrors.add(Label.Error_Property_Member_AML_Field + ' (' + pm.Name__c + '): ' + String.join(missingPropertyMemberAMLFields, ', '));
                            }

                        } else { // Age >70
                            
                            if ( pm.Current_Occupation__c == PropertyMemberService.OCCUPATION_RETIRED ||  pm.Current_Occupation__c == PropertyMemberService.OCCUPATION_UNEMPLOYED ){
                                
                                List<String> missingPropertyMemberAMLOccFields = Utils.missingFields(propertyMemberAMLUnempNoPrevFields, propertyMemberFieldMap, pm);
                                if (!missingPropertyMemberAMLOccFields.isEmpty())
                                    leadErrors.add(Label.Error_Property_Member_AML_Field + ' (' + pm.Name__c + '): ' + String.join(missingPropertyMemberAMLOccFields, ', '));

                            } else if ( pm.Current_Occupation__c != PropertyMemberService.OCCUPATION_NEVER_EMPLOYED && pm.Current_Occupation__c != PropertyMemberService.OCCUPATION_HOMEMAKER ) {

                                List<String> missingPropertyMemberAMLOccFields = Utils.missingFields( propertyMemberAMLAllOtherFields, propertyMemberFieldMap, pm);
                                    if (!missingPropertyMemberAMLOccFields.isEmpty())
                                        leadErrors.add(Label.Error_Property_Member_AML_Field + ' (' + pm.Name__c + '): ' + String.join(missingPropertyMemberAMLOccFields, ', '));
                            } else {

                                List<String> missingPropertyMemberAMLFields = Utils.missingFields(propertyMemberAMLFields, propertyMemberFieldMap, pm);
                                if (!missingPropertyMemberAMLFields.isEmpty())
                                    leadErrors.add(Label.Error_Property_Member_AML_Field + ' (' + pm.Name__c + '): ' + String.join(missingPropertyMemberAMLFields, ', '));
                            }
                        }
                        
                        if (pm.On_Title__c) 
                            onTitleMissing = false;
                    }

                }
                
                if (onTitleMissing) {
                    leadErrors.add(Label.Error_File_Validation_OnTitle);
                }
                // check if the Credit Assessment is required - If is Blanket Mortgage or Property Member is POA / Guarantor, it does not need Credit Assessment.
                if (activePOA == true || activeGuarantor == true || l.Blanket_Mortgage_File__c == true) {
                    l.Credit_Assessment_Required__c = false;
                } else {
                    l.Credit_Assessment_Required__c = true;
                }
                System.debug('!!!!- Credit_Assessmemt-required ='+ l.Credit_Assessment_Required__c);


                // check that the Credit Assessment has been run; not required for POA
                if (l.Credit_Assessment_Required__c == true && l.Credit_Assessment_Successful__c == false) {
                    
                
                    leadErrors.add(Label.Error_File_Validation_CreditAssessment);
                }

            // End Property Member Check 

            // check that an Appraisal has been ordered or flagged to order later
            if (String.isBlank(l.Appraisal_Option__c)) {
                leadErrors.add(Label.Error_File_Validation_Appraisal);
            }
            

            // the Active Quote must be flagged as Eligible
            if (!leadRelatedMap.get(l.Id).Active_Quote__r.Is_Eligible__c) {
                leadErrors.add(Label.Error_File_Validation_ActiveQuote);
            }
            // must have at least one Campaign Member record
            if(leadRelatedMap.get(l.Id).Campaign_Member_Count__c == 0) {
                leadErrors.add(Label.Error_Lead_MissingCampaign);
            }
            
            System.debug('events? ' + leadRelatedMap.get(l.Id).Events);
            if(leadRelatedMap.get(l.Id).RecordType.DeveloperName == LEAD_RT_CONSUMER && leadRelatedMap.get(l.Id).Events.size() == 0) {
                leadErrors.add(Label.Error_Consumer_Missing_InitialContact);
            }
            
            if (!leadErrors.isEmpty()) {
                l.File_Validation_Error__c = true;
                l.Missing_MARS_Validation_Message__c = '<ul><li>' + String.join(leadErrors, '</li><li>') + '</li></ul>';
            } else {
                l.File_Validation_Error__c = false;
                l.Missing_MARS_Validation_Message__c = null;
            }
            l.MARS_Validation_Run__c = true;
        }
    }

    
    /*
     * HEB-405: File Valdiation prior to Launch to MARS
     * HEB-443: File Validation moved from Opportunity to Lead
     * - ensure the Lead and related records (Property, Property Member, Quote) are all in good standing before trying to integrate w/ MARS
     */
    public void ensureFileComplete(List<Lead> records, Map<Id, Lead> oldRecords)
    {
        List<Lead> requireMarsValidation = new List<Lead>();
        for (Lead l : records) {
            if (l.IsConverted && !oldRecords.get(l.Id).IsConverted && !l.MARS_Validation_Run__c) {
                l.Status = LEAD_STATUS_PREAPPLICATION;
                requireMarsValidation.add(l); 
            }
        }

        if(!requireMarsValidation.isEmpty())
            fileValidationPriorToMARS(requireMarsValidation, oldRecords);
        
        // get relevant records; return if none
        for (Lead l : records) {
            if (l.IsConverted && !oldRecords.get(l.Id).IsConverted) {
                if(l.Missing_MARS_Validation_Message__c <> null)
                    l.addError(Label.Error_Lead_FileIncomplete);
            }
        }
    }

    
    /*
     * HEB-402: set the Numeric Phone field based on the Phone
     */ 
    public void setNumericPhone(List<Lead> records, Map<Id, Lead> oldRecords) {
        for(Lead l : records) {
            if(oldRecords == null || oldRecords.get(l.Id).Phone <> l.Phone || (l.Phone <> null && l.Numeric_Phone__c == null)) {
                if(l.Phone == null)
                    l.Numeric_Phone__c = null;
                else {
                    String numericPhone = l.Phone;
                    numericPhone = numericPhone.replace('(','');
                    numericPhone = numericPhone.replace(')','');
                    numericPhone = numericPhone.replace(' ','');
                    numericPhone = numericPhone.replace('-','');
                    l.Numeric_Phone__c = numericPhone;
                }
            }
        }    
    }


    /*
     * HEB-402: set the Numeric Phone field based on the Phone
     */ 
    public void setAreaCode(List<Lead> records, Map<Id, Lead> oldRecords) {
        for(Lead l : records) {
            if(oldRecords == null || oldRecords.get(l.Id).Numeric_Phone__c <> l.Numeric_Phone__c) {
                if(l.Numeric_Phone__c == null)
                    l.Numeric_Phone__c = null;
                else {
                    if(l.Numeric_Phone__c.length() <= 10) {
                        l.Area_Code__c = l.Numeric_Phone__c.left(3);
                    } else {
                        l.Area_Code__c = l.Numeric_Phone__c.substring(1,4);
                    }
                }
            }
        }    
    }

    /*
     * HEB-596: Only currently active user can be set to CASL consent
     */ 
    public void checkCASLConsentUser(List<Lead> records, Map<Id, Lead> oldRecords)
    {
        if (Utils.allowBypassForUser()) return;

        for (Lead l : records)
        {
            // Only do this for Account creation outside of Lead Conversion.
            if (l.Converted_Lead_Check__c != null) continue;

            if (l.CASL_Content_Obtained_By__c <> UserInfo.getUserId()
                && l.Email <> null
                && l.Email <> ''
            )
            {
                if (oldRecords == null
                    // If this is an update check if the user is trying to change the consent field.
                    || (l.CASL_Content_Obtained_By__c <> oldRecords.get(l.Id).CASL_Content_Obtained_By__c))
                {
                    l.addError(Label.Error_Only_Active_CASL_User_Can_Conset);
                }
            }
        }
    }

    /* HEB-560 Ensure specialist counter decrements on lead re-asignment */
    public void checkDecrementSpecialist(List<Lead> records, Map<Id, Lead> oldRecords) {
        //Check if lead is getting reassigned
        List<Id> oldUserIds = new List<Id>();
        for(Lead l : records) {
            Lead oldL = oldRecords.get(l.Id);
            if(l.OwnerId != oldL.OwnerId) {
                oldUserIds.add(oldL.OwnerId);
            }
        }
        
        //Check if previous lead assignment was a specialist
        Map<Id, Specialist__c> spls = new Map<Id, Specialist__c>([
            SELECT Id
            FROM Specialist__c
            WHERE User__c IN :oldUserIds
        ]);
        
        // Increase lead assigned count.
        LeadAssignmentService.decrementAssignmentCount(spls.keySet());

    }

    
    // set Lead Conversion context in beforeUpdate context to make available to other objects
    public void setLeadConversionFlag(List<Lead> newLeads, Map<Id, Lead> oldLeadMap)
    {
        for (Lead l : newLeads)
        {
            if (l.IsConverted == true && oldLeadMap.get(l.Id).IsConverted == false)
            {
                isLeadConversion = true;
            }
        }

        
    }

    
    /*
        HEB-832: post-conversion, callout to generate MARS Ready Record
    */
    public static void startMarsReadyRecordPostConversion(List<Lead> newLeads, Map<Id, Lead> oldLeadMap)
    {
        List<Id> oppIds = new List<Id>();
        for (Lead l : newLeads)
        {
            if (l.IsConverted == true && oldLeadMap.get(l.Id).IsConverted == false) 
            {
                oppIds.add(l.ConvertedOpportunityId);
            }
        }

        // if no converted leads, no action
        if (oppIds.isEmpty()) return;
        
        List<Opportunity> oppList = [
            SELECT Id, Name
            FROM Opportunity
            WHERE Id IN :oppIds
        ];

        OpportunityService service = new OpportunityService();
        service.sendToMarsPlatformEvent(oppList);
    }


    /*
        Moved from process builder; set Bio fields for user
    */
    public void mapUserBio(List<Lead> newLeads, Map<Id, Lead> oldRecords)
    {
        Set<String> fieldsToCheck = new Set<String>{'OwnerId'};

        List<Lead> ls = (oldRecords == null) ?
            newLeads : 
            (List<Lead>) Utils.getChangedObjects(newLeads, oldRecords, fieldsToCheck);
        
        List<Id> userIds = new List<Id>();

        for(Lead ld : ls) {
            String ownerId = ld.OwnerId;
            if(ownerId.startsWith('005'))
                userIds.add(ld.OwnerId);
        }        

        if(userIds.isEmpty())
            return;
        
        Map<Id, User> userMap = new Map<Id, User> ([select Id, English_Bio_URL__c, French_Bio_URL__c from User where Id IN :userIds]);

        for(Lead ld : ls) {
            ld.Owners_English_Bio_URL__c = userMap.get(ld.OwnerId).English_Bio_URL__c;
            ld.Owners_French_Bio_URL__c = userMap.get(ld.OwnerId).French_Bio_URL__c;
        }
    }    

    /*
     * New Lead - 
     * Set Verify_Email__c to true if Email field has value. 
     * Set Most Recent Inquiry Date to Datetime.now() if it doesn't have value.
     */
    public void initialValues(List<Lead> records)
    {
        
        for (Lead ld : records)
        {
            if (ld.Email != null)
            {
                ld.verify_email__c = true;
            }
            if (ld.Most_Recent_Inquiry_Date__c == null)
            {
                ld.Most_Recent_Inquiry_Date__c = Datetime.now(); 
            } 
        }
    }

    /*
     * HEB-xxx: Update Lead - Set Verify_Email__c to true if Email is Changed. 
     */
    public void updateVerifyEmail(List<Lead> records, Map<Id, Lead> oldRecords)
    {
        List<Lead> ldToUpdate = new List<Lead>();
        for (Lead l : records)
        {
            Lead ol = oldRecords.get(l.Id);
            if (l.Email != null && l.Email != ol.Email)
            {
                
                l.Email_Verification_Status__c = null;
                l.Email_Verification_Result__c = null;
                l.Verify_Email__c = true;
            }
            ldToUpdate.add(l);
        }
    }        
    
    public static void mapRelatedRecordsFileRecordType(List<Lead> newLeads, Map<Id, Lead> oldRecords)
    {
        Set<String> fieldsToCheck = new Set<String>{'RecordTypeId'};

        List<Lead> ls = (List<Lead>) Utils.getChangedObjects(newLeads, oldRecords, fieldsToCheck);
        Map<Id, Lead> leadMap = new MAp<Id, Lead>();

        for(Lead ld : ls) 
            leadMap.put( ld.Id, ld );

        if (leadMap.isEmpty() ) return;
            processRelatedRecordsFileRecordType(leadMap);
    }
        
    /*
     * HEB-890:  
     */
    
    public static void processRelatedRecordsFileRecordType(Map<Id, Lead> leadMap)
    {
        List<Debt__c> debtList                  = new List<Debt__c>();
        List<Quote__c> quoteList                = new List<Quote__c>();
        List<Membership__c> membershipList      = new List<Membership__c>();
        List<Appraisal__c> appraisalList        = new List<Appraisal__c>();
        List<Appraisal_Order__c> apprOrderList  = new List<Appraisal_Order__c>();
        List<Property_Member__c> propertyMemList= new List<Property_Member__c>();
        List<Credit_Report__c> creditReportList = new List<Credit_Report__c>(); 
        //Map<Id, Property__c> propertyList = new Map<Id, Property__c>();

        for (Lead l : [
            SELECT Id, Recordtypeid, recordtype.name, Property__c, 
            (
            SELECT Id, Lead__c, File_Record_type__c
                FROM Debts__r
            ),
            (
            SELECT Id, Lead__c, File_Record_type__c
                FROM Quotes__r
            ),
            (
            SELECT Id, Lead__c, File_Record_type__c
                FROM Memberships__r
            ),
            (
            SELECT Id, Lead__c, File_Record_type__c
                FROM Appraisals__r
            ),
            (
            SELECT Id, Lead__c, File_Record_type__c
                FROM Property_Members__r
            )
            FROM Lead
            WHERE Id IN :leadMap.keySet()
        ])
        {
            //if(l.Property__c <> null)
            //    propertyList.put(l.Property__c, new Property__c(Id = l.Property__c, OwnerId = l.OwnerId));
            
            for (Debt__c debt : l.Debts__r)
            {
                    debtList.add(debt);
            }
            for (Quote__c quote : l.Quotes__r)
            {
                    quoteList.add(quote);
            }
            for (Membership__c membership : l.Memberships__r)
            {
                    membershipList.add(membership);

            }
            for (Appraisal__c appraisal : l.Appraisals__r)
            {
                    appraisalList.add(appraisal);
            }
            
            for (Property_Member__c pm : l.Property_Members__r)
            {
                    propertyMemList.add(pm);
            }    
        }

        for (Appraisal_Order__c apprOrder : [SELECT Id, Appraisal__c, Appraisal__r.Lead__c FROM Appraisal_Order__c 
                                            WHERE  Appraisal__r.Lead__c =: leadMap.keySet()])
        {
                apprOrderList.add(apprOrder);
        }

        for (Credit_Report__c creditReport : [SELECT Id, Property_Member__c, Property_Member__r.Lead__c FROM Credit_Report__c WHERE Property_Member__r.Lead__c =: leadMap.keySet()])
        {   
            creditReportList.add( creditReport );
        }

        Boolean reassignmentError = false;
        
        try{
            update debtList;
        } catch ( Exception e ){
            reassignmentError = true;
            system.debug( e.getMessage() );
        }

        try{
            update quoteList;
        } catch ( Exception e ){
            reassignmentError = true;
            system.debug( e.getMessage() );
        }

        try{
            update membershipList;
        } catch ( Exception e ){
            reassignmentError = true;
            system.debug( e.getMessage() );
        }

        try{
            update appraisalList;
        } catch ( Exception e ){
            reassignmentError = true;
            system.debug( e.getMessage() );
        }

        try{
            update apprOrderList;
        } catch ( Exception e ){
            reassignmentError = true;
            system.debug( e.getMessage() );
        }

        try{
            update propertyMemList;
        } catch ( Exception e ){
            reassignmentError = true;
            system.debug( e.getMessage() );
        }

        try{
            update creditReportList;
        } catch ( Exception e ){
            reassignmentError = true;
            system.debug( e.getMessage() );
        }

        // if there was an eror reassigning any of the records, queue up a retry
       /*
        if(reassignmentError) {
            List<Id> leadIds = new List<Id>();
            leadIds.addAll(leadMap.keySet());
            LeadOwnershipRetry updateJob = new LeadOwnershipRetry(leadIds);
            ID jobID = System.enqueueJob(updateJob);               
        }
        */
    }


}