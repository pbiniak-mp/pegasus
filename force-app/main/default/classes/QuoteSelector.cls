public inherited sharing class QuoteSelector {

	public static List<Quote> getQuotesByIds(Set<Id> quoteIds) {
		return [
			SELECT
				Id,
				QuoteNumber,
				Name,
//				Rev_Number__c,
				ContactId,
				ExpirationDate,
				CreatedDate,
				BillingName,
				BillingStreet,
				BillingCity,
				BillingState,
				BillingPostalCode,
				BillingCountry,
				OpportunityId,
				Opportunity.Name,
				Opportunity.Project_Wattage_kW__c,
				Opportunity.Module_Wattage_W__c,
				Opportunity.Module_Quantity__c,
				Opportunity.System_Type__c,
				Opportunity.Panel_Tilt__c,
				Opportunity.Panel_Orientation__c,
				Opportunity.Product_Line__c,
				Opportunity.System_Configuration__c,
				Opportunity.Roof_Surface__c,
				Opportunity.Roof_Pitch__c,
				Opportunity.Building_Height_ft__c,
				Opportunity.Parapet_Height_in__c,
				Opportunity.Parapet_Width_in__c,
				Opportunity.Setback_Distance_ft__c,
				Opportunity.Structural_Load_Limit_psf__c,
				Opportunity.Point_Load_Limit_psf__c,
				Opportunity.Maximum_System_Weight_Limit_lbs__c,
				Opportunity.Existing_or_new_construction__c,
				Opportunity.Planned_Install_Date__c,
				Opportunity.Project_Notes__c
			FROM Quote
			WHERE Id IN :quoteIds
		];
	}

	public static Quote getQuoteById(Id quoteId) {
		List<Quote> quotes = getQuotesByIds(new Set<Id>{ quoteId });
		return quotes.isEmpty() ? null : quotes[0];
	}
}