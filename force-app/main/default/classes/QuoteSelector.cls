public inherited sharing class QuoteSelector {

	public static List<Quote> getQuotesByIds(Set<Id> quoteIds) {
		return [
			SELECT
				BillingCity,
				BillingCountry,
				BillingName,
				BillingPostalCode,
				BillingState,
				BillingStreet,
				ContactId,
				CreatedDate,
				Design_Revision__c,
				ExpirationDate,
				Id,
				Name,
				OpportunityId,
				QuoteNumber,
				Opportunity.Building_Height_ft__c,
				Opportunity.Existing_or_new_construction__c,
				Opportunity.Maximum_System_Weight_Limit_lbs__c,
				Opportunity.Module_Quantity__c,
				Opportunity.Module_Wattage_W__c,
				Opportunity.Name,
				Opportunity.Panel_Orientation__c,
				Opportunity.Panel_Tilt__c,
				Opportunity.Parapet_Height_in__c,
				Opportunity.Parapet_Width_in__c,
				Opportunity.Planned_Install_Date__c,
				Opportunity.Point_Load_Limit_psf__c,
				Opportunity.Product_Line__c,
				Opportunity.Project_Notes__c,
				Opportunity.Project_Wattage_kW__c,
				Opportunity.Roof_Pitch__c,
				Opportunity.Roof_Surface__c,
				Opportunity.Setback_Distance_ft__c,
				Opportunity.Structural_Load_Limit_psf__c,
				Opportunity.System_Configuration__c,
				Opportunity.System_Type__c,
				Design_Revision__r.Building_Height_ft__c,
				Design_Revision__r.Existing_or_new_construction__c,
				Design_Revision__r.Is_Active__c,
				Design_Revision__r.Maximum_System_Weight_Limit_lbs__c,
				Design_Revision__r.Module_Quantity__c,
				Design_Revision__r.Module_Wattage_W__c,
				Design_Revision__r.Panel_Orientation__c,
				Design_Revision__r.Panel_Tilt__c,
				Design_Revision__r.Parapet_Height_in__c,
				Design_Revision__r.Parapet_Width_in__c,
				Design_Revision__r.Planned_Install_Date__c,
				Design_Revision__r.Point_Load_Limit_psf__c,
				Design_Revision__r.Product_Line__c,
				Design_Revision__r.Project_Notes__c,
				Design_Revision__r.Project_Wattage_kW__c,
				Design_Revision__r.Revision_Number__c,
				Design_Revision__r.Revision_Reason__c,
				Design_Revision__r.Roof_Pitch__c,
				Design_Revision__r.Roof_Surface__c,
				Design_Revision__r.Setback_Distance_ft__c,
				Design_Revision__r.Status__c,
				Design_Revision__r.Structural_Load_Limit_psf__c,
				Design_Revision__r.System_Configuration__c,
				Design_Revision__r.System_Type__c
			FROM Quote
			WHERE Id IN :quoteIds
		];
	}

	public static List<Quote> getQuotesByDesignRevisionId(Id revisionId) {
		return [
			SELECT
				Id,
				Name,
				OpportunityId,
				Status,
				Quote_Type__c,
				Quote_Grand_Total__c
			FROM Quote
			WHERE Design_Revision__c = :revisionId
			ORDER BY Quote_Type__c, CreatedDate ASC
		];
	}

	public static Quote getQuoteById(Id quoteId) {
		List<Quote> quotes = getQuotesByIds(new Set<Id>{ quoteId });
		return quotes.isEmpty() ? null : quotes[0];
	}
}