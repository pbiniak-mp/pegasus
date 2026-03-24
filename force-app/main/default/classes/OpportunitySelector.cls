public inherited sharing class OpportunitySelector {

	public static List<Opportunity> getOpportunitiesByIds(Set<Id> ids) {
		return [
			SELECT
				Id,
				Building_Height_ft__c,
				CloseDate,
				Design_Revision__c,
				Existing_or_new_construction__c,
				Maximum_System_Weight_Limit_lbs__c,
				Module_Quantity__c,
				Module_Wattage_W__c,
				Name,
				Panel_Orientation__c,
				Panel_Tilt__c,
				Parapet_Height_in__c,
				Parapet_Width_in__c,
				Planned_Install_Date__c,
				Point_Load_Limit_psf__c,
				Product_Line__c,
				Project_Notes__c,
				Project_Wattage_kW__c,
				Roof_Pitch__c,
				Roof_Surface__c,
				Setback_Distance_ft__c,
				StageName,
				Structural_Load_Limit_psf__c,
				System_Configuration__c,
				System_Type__c
			FROM Opportunity
			WHERE Id IN :ids
		];
	}

	public static Opportunity getOpportunityById(Id id) {
		List<Opportunity> records = getOpportunitiesByIds(new Set<Id>{ id });
		return records.isEmpty() ? null : records[0];
	}
}
