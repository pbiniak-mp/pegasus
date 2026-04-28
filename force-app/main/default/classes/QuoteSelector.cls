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
				GrandTotal,
				Id,
				Name,
				ShippingHandling,
				OpportunityId,
				QuoteNumber,
				Quote_Number__c,
				TotalPrice,
				Opportunity.Array_Azimuth__c,
				Opportunity.Ballast_Block_Specification__c,
				Opportunity.Building_Height_ft__c,
				Opportunity.Code_Standard__c,
				Opportunity.DesignPreference__c,
//				Opportunity.Distributor__c,
				Opportunity.Existing_or_new_construction__c,
				Opportunity.Exposure_Category__c,
				Opportunity.Ground_Slope__c,
				Opportunity.Landfill_Location__c,
				Opportunity.LegalConsent__c,
				Opportunity.Maximum_System_Weight_Limit_lbs__c,
				Opportunity.Module_Length_mm__c,
				Opportunity.Module_Manufacturer__c,
				Opportunity.Module_Model_Number__c,
				Opportunity.Module_Quantity_F__c,
				Opportunity.Module_Wattage_Text__c,
				Opportunity.Module_Wattage_W__c,
				Opportunity.Module_Wattage__c,
				Opportunity.Module_Weight_lbs__c,
				Opportunity.Module_Width_mm__c,
				Opportunity.Name,
				Opportunity.Panel_Orientation__c,
				Opportunity.Panel_Tilt__c,
				Opportunity.Parapet_Height_in__c,
				Opportunity.Parapet_Width_in__c,
				Opportunity.Planned_Install_Date__c,
				Opportunity.Point_Load_Limit_psf__c,
				Opportunity.Product_Line__c,
				Opportunity.ProjectName__c,
				Opportunity.Project_Notes__c,
				Opportunity.Project_Wattage_kW__c,
				Opportunity.Risk_Category__c,
				Opportunity.Roof_Pitch__c,
				Opportunity.Roof_Surface__c,
				Opportunity.Setback_Distance_ft__c,
				Opportunity.Structural_Load_Limit_psf__c,
				Opportunity.System_Configuration__c,
				Opportunity.System_Type__c,
				Opportunity.UL_3741_compliance__c,
				Opportunity.Wind_Speed_mph__c,
				Design_Revision__r.Array_Azimuth__c,
				Design_Revision__r.Ballast_Block_Specification__c,
				Design_Revision__r.Building_Height_ft__c,
				Design_Revision__r.Code_Standard__c,
				Design_Revision__r.DesignPreference__c,
				Design_Revision__r.Distributor__c,
				Design_Revision__r.Existing_or_new_construction__c,
				Design_Revision__r.Exposure_Category__c,
				Design_Revision__r.Ground_Slope__c,
				Design_Revision__r.Is_Active__c,
				Design_Revision__r.Landfill_Location__c,
				Design_Revision__r.LegalConsent__c,
				Design_Revision__r.Maximum_System_Weight_Limit_lbs__c,
				Design_Revision__r.Module_Length_mm__c,
				Design_Revision__r.Module_Manufacturer__c,
				Design_Revision__r.Module_Model_Number__c,
				Design_Revision__r.Module_Quantity_F__c,
				Design_Revision__r.Module_Wattage_Text__c,
				Design_Revision__r.Module_Wattage_W__c,
				Design_Revision__r.Module_Wattage__c,
				Design_Revision__r.Module_Weight_lbs__c,
				Design_Revision__r.Module_Width_mm__c,
				Design_Revision__r.Panel_Orientation__c,
				Design_Revision__r.Panel_Tilt__c,
				Design_Revision__r.Parapet_Height_in__c,
				Design_Revision__r.Parapet_Width_in__c,
				Design_Revision__r.Planned_Install_Date__c,
				Design_Revision__r.Point_Load_Limit_psf__c,
				Design_Revision__r.Product_Line__c,
				Design_Revision__r.ProjectName__c,
				Design_Revision__r.Project_Notes__c,
				Design_Revision__r.Project_Wattage_kW__c,
				Design_Revision__r.Revision_Number__c,
				Design_Revision__r.Revision_Reason__c,
				Design_Revision__r.Risk_Category__c,
				Design_Revision__r.Roof_Pitch__c,
				Design_Revision__r.Roof_Surface__c,
				Design_Revision__r.Setback_Distance_ft__c,
				Design_Revision__r.Status__c,
				Design_Revision__r.Structural_Load_Limit_psf__c,
				Design_Revision__r.System_Configuration__c,
				Design_Revision__r.System_Type__c,
				Design_Revision__r.UL_3741_compliance__c,
				Design_Revision__r.Wind_Speed_mph__c
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
				Quote_Grand_Total__c,
				ExpirationDate,
				Design_Revision__r.Revision_Number__c,
				CreatedBy.Name,
				(SELECT Id, Quantity, UnitPrice, Description, Product2.Name
				 FROM QuoteLineItems
				 ORDER BY SortOrder ASC NULLS LAST)
			FROM Quote
			WHERE Design_Revision__c = :revisionId
			ORDER BY Quote_Type__c, CreatedDate DESC
		];
	}

	public static Quote getQuoteById(Id quoteId) {
		List<Quote> quotes = getQuotesByIds(new Set<Id>{ quoteId });
		return quotes.isEmpty() ? null : quotes[0];
	}
}