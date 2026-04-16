public inherited sharing class DesignRevisionSelector {

	public static List<Design_Revision__c> getDesignRevisionsByIds(Set<Id> ids) {
		return [
			SELECT
				Id,
				Building_Height_ft__c,
				Code_Standard__c,
				Existing_or_new_construction__c,
				Exposure_Category__c,
				Is_Active__c,
				Maximum_System_Weight_Limit_lbs__c,
				Module_Length_mm__c,
				Module_Manufacturer__c,
				Module_Model_Number__c,
				Module_Quantity_F__c,
				Module_Wattage__c,
				Module_Wattage_W__c,
				Module_Weight_lbs__c,
				Module_Width_mm__c,
				Opportunity__c,
				Panel_Orientation__c,
				Panel_Tilt__c,
				Parapet_Height_in__c,
				Parapet_Width_in__c,
				Planned_Install_Date__c,
				Point_Load_Limit_psf__c,
				Product_Line__c,
				Project_Notes__c,
				Project_Wattage_kW__c,
				Revision_Number__c,
				Revision_Reason__c,
				Risk_Category__c,
				Roof_Pitch__c,
				Roof_Surface__c,
				Setback_Distance_ft__c,
				Status__c,
				Structural_Load_Limit_psf__c,
				System_Configuration__c,
				System_Type__c,
				Wind_Speed_mph__c
			FROM Design_Revision__c
			WHERE Id IN :ids
		];
	}

	public static Design_Revision__c getDesignRevisionById(Id id) {
		List<Design_Revision__c> records = getDesignRevisionsByIds(new Set<Id>{ id });
		return records.isEmpty() ? null : records[0];
	}

	public static List<Design_Revision__c> getRevisionsByOpportunityIds(Set<Id> opportunityIds) {
		return [
			SELECT
				Id,
				Is_Active__c,
				Opportunity__c
			FROM Design_Revision__c
			WHERE Opportunity__c IN :opportunityIds
		];
	}

	public static List<Design_Revision__c> getHierarchyFieldsByOpportunityId(Id opportunityId) {
		return [
			SELECT
				Id,
				Name,
				Revision_Number__c,
				Revision_Reason__c,
				Project_Notes__c,
				Parent_Revision__c
			FROM Design_Revision__c
			WHERE Opportunity__c = :opportunityId
			ORDER BY Revision_Number__c ASC NULLS LAST
		];
	}

	public static List<Design_Revision__c> getRevisionsByOpportunityId(Id opportunityId) {
		return [
			SELECT
				Id,
				Name,
				Status__c,
				Is_Active__c,
				Project_Wattage_kW__c,
				System_Type__c,
				Roof_Surface__c,
				Project_Notes__c,
				CreatedDate,
				LastModifiedDate,
				CreatedBy.Name
			FROM Design_Revision__c
			WHERE Opportunity__c = :opportunityId
			ORDER BY CreatedDate DESC
		];
	}
}
