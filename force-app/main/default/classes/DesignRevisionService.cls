public with sharing class DesignRevisionService {
	private static final String CLASS_NAME = 'DesignRevisionService';
	private static final String ERR_DEACTIVATE_REVISIONS = 'Failed to deactivate other Design Revisions';
	private static final String ERR_DELETE_CONTENT_LINKS = 'Failed to delete ContentDocumentLinks from Opportunity';
	private static final String ERR_INSERT_CONTENT_LINKS = 'Failed to insert ContentDocumentLinks to Opportunity';
	private static final String ERR_UPDATE_OPPORTUNITIES = 'Failed to update Opportunities after Design Revision activation';
	private static final String ERR_CREATE_NEW_REVISION = 'Unhandled error during createNewRevision';

	public static List<Design_Revision__c> filterActivated(
		List<Design_Revision__c> newList,
		Map<Id, Design_Revision__c> oldMap
	) {
		List<Design_Revision__c> result = new List<Design_Revision__c>();
		for (Design_Revision__c dr : newList) {
			Boolean wasActive = oldMap != null && oldMap.get(dr.Id).Is_Active__c == true;
			if (dr.Is_Active__c == true && !wasActive) {
				result.add(dr);
			}
		}
		return result;
	}

	public static void handleActivation(List<Design_Revision__c> activatedRevisions) {
		Map<Id, Design_Revision__c> oppIdToActiveRevision = buildOppToRevisionMap(activatedRevisions);
		Set<Id> oppIds = oppIdToActiveRevision.keySet();

		Set<Id> activeRevisionIds = new Set<Id>();
		for (Design_Revision__c dr : oppIdToActiveRevision.values()) {
			activeRevisionIds.add(dr.Id);
		}

		List<Design_Revision__c> allRevisions = DesignRevisionSelector.getRevisionsByOpportunityIds(oppIds);
		Set<Id> allRevisionIds = new Set<Id>();
		for (Design_Revision__c dr : allRevisions) {
			allRevisionIds.add(dr.Id);
		}

		deactivateOtherRevisions(allRevisions, activeRevisionIds);
		relinkFiles(oppIds, oppIdToActiveRevision, activeRevisionIds, allRevisionIds);
		updateOpportunities(oppIdToActiveRevision);
	}

	private static Map<Id, Design_Revision__c> buildOppToRevisionMap(List<Design_Revision__c> revisions) {
		Map<Id, Design_Revision__c> result = new Map<Id, Design_Revision__c>();
		for (Design_Revision__c dr : revisions) {
			result.put(dr.Opportunity__c, dr);
		}
		return result;
	}

	private static void deactivateOtherRevisions(
		List<Design_Revision__c> allRevisions,
		Set<Id> activeRevisionIds
	) {
		List<Design_Revision__c> toDeactivate = new List<Design_Revision__c>();
		for (Design_Revision__c dr : allRevisions) {
			if (!activeRevisionIds.contains(dr.Id) && dr.Is_Active__c) {
				toDeactivate.add(new Design_Revision__c(Id = dr.Id, Is_Active__c = false));
			}
		}
		if (!toDeactivate.isEmpty()) {
			TriggerHandler.bypass(Constants.DESIGN_REVISION_HANDLER_NAME);
			try {
				update toDeactivate;
			} catch (Exception e) {
				BoltErrorLogger.logError(
					CLASS_NAME,
					'deactivateOtherRevisions',
					ERR_DEACTIVATE_REVISIONS + ': ' + e.getMessage(),
					e.getStackTraceString(),
					Constants.SOURCE_TYPE_APEX,
					Constants.SEVERITY_ERROR,
					UserInfo.getUserId(),
					null
				);
				throw e;
			} finally {
				TriggerHandler.clearBypass(Constants.DESIGN_REVISION_HANDLER_NAME);
			}
		}
	}

	private static void relinkFiles(
		Set<Id> oppIds,
		Map<Id, Design_Revision__c> oppIdToActiveRevision,
		Set<Id> activeRevisionIds,
		Set<Id> allRevisionIds
	) {
		List<ContentDocumentLink> revisionCDLs = ContentDocumentLinkSelector.getByLinkedEntityIds(allRevisionIds);

		Set<Id> revisionDocIds = new Set<Id>();
		for (ContentDocumentLink cdl : revisionCDLs) {
			revisionDocIds.add(cdl.ContentDocumentId);
		}

		List<ContentDocumentLink> oppCDLs = ContentDocumentLinkSelector.getByLinkedEntityIds(oppIds);
		List<ContentDocumentLink> toDelete = new List<ContentDocumentLink>();
		for (ContentDocumentLink cdl : oppCDLs) {
			if (revisionDocIds.contains(cdl.ContentDocumentId)) {
				toDelete.add(cdl);
			}
		}
		if (!toDelete.isEmpty()) {
			try {
				delete toDelete;
			} catch (Exception e) {
				BoltErrorLogger.logError(
					CLASS_NAME,
					'relinkFiles',
					ERR_DELETE_CONTENT_LINKS + ': ' + e.getMessage(),
					e.getStackTraceString(),
					Constants.SOURCE_TYPE_APEX,
					Constants.SEVERITY_ERROR,
					UserInfo.getUserId(),
					null
				);
				throw e;
			}
		}

		Map<Id, Id> activeRevIdToOppId = new Map<Id, Id>();
		for (Id oppId : oppIdToActiveRevision.keySet()) {
			activeRevIdToOppId.put(oppIdToActiveRevision.get(oppId).Id, oppId);
		}

		List<ContentDocumentLink> toInsert = new List<ContentDocumentLink>();
		for (ContentDocumentLink cdl : revisionCDLs) {
			if (activeRevisionIds.contains(cdl.LinkedEntityId)) {
				toInsert.add(
					new ContentDocumentLink(
						ContentDocumentId = cdl.ContentDocumentId,
						LinkedEntityId = activeRevIdToOppId.get(cdl.LinkedEntityId),
						ShareType = cdl.ShareType,
						Visibility = cdl.Visibility
					)
				);
			}
		}
		if (!toInsert.isEmpty()) {
			try {
				insert toInsert;
			} catch (Exception e) {
				BoltErrorLogger.logError(
					CLASS_NAME,
					'relinkFiles',
					ERR_INSERT_CONTENT_LINKS + ': ' + e.getMessage(),
					e.getStackTraceString(),
					Constants.SOURCE_TYPE_APEX,
					Constants.SEVERITY_ERROR,
					UserInfo.getUserId(),
					null
				);
				throw e;
			}
		}
	}

	private static void updateOpportunities(Map<Id, Design_Revision__c> oppIdToActiveRevision) {
		List<Opportunity> toUpdate = new List<Opportunity>();
		for (Id oppId : oppIdToActiveRevision.keySet()) {
			toUpdate.add(buildOpportunity(oppId, oppIdToActiveRevision.get(oppId)));
		}
		if (!toUpdate.isEmpty()) {
			try {
				update toUpdate;
			} catch (Exception e) {
				BoltErrorLogger.logError(
					CLASS_NAME,
					'updateOpportunities',
					ERR_UPDATE_OPPORTUNITIES + ': ' + e.getMessage(),
					e.getStackTraceString(),
					Constants.SOURCE_TYPE_APEX,
					Constants.SEVERITY_ERROR,
					UserInfo.getUserId(),
					null
				);
				throw e;
			}
		}
	}

	private static Opportunity buildOpportunity(Id oppId, Design_Revision__c dr) {
		return new Opportunity(
			Id = oppId,
			Design_Revision__c = dr.Id,
			Building_Height_ft__c = dr.Building_Height_ft__c,
			Code_Standard__c = dr.Code_Standard__c,
			Existing_or_new_construction__c = dr.Existing_or_new_construction__c,
			Exposure_Category__c = dr.Exposure_Category__c,
			Maximum_System_Weight_Limit_lbs__c = dr.Maximum_System_Weight_Limit_lbs__c,
			Module_Length_mm__c = dr.Module_Length_mm__c,
			Module_Manufacturer__c = dr.Module_Manufacturer__c,
			Module_Model_Number__c = dr.Module_Model_Number__c,
			Module_Wattage_W__c = dr.Module_Wattage_W__c,
			Module_Weight_lbs__c = dr.Module_Weight_lbs__c,
			Module_Width_mm__c = dr.Module_Width_mm__c,
			Panel_Orientation__c = dr.Panel_Orientation__c,
			Panel_Tilt__c = dr.Panel_Tilt__c,
			Parapet_Height_in__c = dr.Parapet_Height_in__c,
			Parapet_Width_in__c = dr.Parapet_Width_in__c,
			Planned_Install_Date__c = dr.Planned_Install_Date__c,
			Point_Load_Limit_psf__c = dr.Point_Load_Limit_psf__c,
			Product_Line__c = dr.Product_Line__c,
			Project_Notes__c = dr.Project_Notes__c,
			Project_Wattage_kW__c = dr.Project_Wattage_kW__c,
			Risk_Category__c = dr.Risk_Category__c,
			Roof_Pitch__c = dr.Roof_Pitch__c,
			Roof_Surface__c = dr.Roof_Surface__c,
			Setback_Distance_ft__c = dr.Setback_Distance_ft__c,
			Structural_Load_Limit_psf__c = dr.Structural_Load_Limit_psf__c,
			System_Configuration__c = dr.System_Configuration__c,
			System_Type__c = dr.System_Type__c,
			Wind_Speed_mph__c = dr.Wind_Speed_mph__c
		);
	}

	public static void buildNames(List<Design_Revision__c> revisions, Map<Id, Design_Revision__c> oldMap) {
		Set<Id> oppIds = new Set<Id>();
		for (Design_Revision__c rev : revisions) {
			Boolean isInsert = oldMap == null;
			Boolean revNumChanged = !isInsert && oldMap.get(rev.Id).Revision_Number__c != rev.Revision_Number__c;
			if (isInsert || revNumChanged) {
				oppIds.add(rev.Opportunity__c);
			}
		}

		if (oppIds.isEmpty()) return;

		Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>(
			OpportunitySelector.getOpportunitiesByIds(oppIds)
		);

		for (Design_Revision__c rev : revisions) {
			Boolean isInsert = oldMap == null;
			Boolean revNumChanged = !isInsert && oldMap.get(rev.Id).Revision_Number__c != rev.Revision_Number__c;
			if (isInsert || revNumChanged) {
				Opportunity opp = oppMap.get(rev.Opportunity__c);
				String accountName = (opp != null && opp.Account != null) ? opp.Account.Name : Constants.DESIGN_REVISION_UNKNOWN_ACCOUNT;
				String revNum = String.isNotBlank(rev.Revision_Number__c) ? rev.Revision_Number__c : Constants.DESIGN_REVISION_NAME_DEFAULT_NUMBER;
				rev.Name = accountName + ' (' + Constants.DESIGN_REVISION_NAME_PREFIX + revNum + ')';
			}
		}
	}

	public static Id createNewRevision(Id currentRevisionId, String revisionReason, String projectNotes) {
		try {
			Design_Revision__c current = DesignRevisionSelector.getDesignRevisionById(currentRevisionId);

			Integer count = [
				SELECT COUNT()
				FROM Design_Revision__c
				WHERE Opportunity__c = :current.Opportunity__c
			];
			String nextNumber = count < 10 ? '0' + String.valueOf(count) : String.valueOf(count);

			Design_Revision__c newRev = new Design_Revision__c(
				Opportunity__c = current.Opportunity__c,
				Parent_Revision__c = currentRevisionId,
				Revision_Number__c = nextNumber,
				Revision_Reason__c = revisionReason,
				Project_Notes__c = projectNotes,
				Is_Active__c = false,
				Status__c = Constants.DESIGN_REVISION_STATUS_NOT_STARTED,
				Building_Height_ft__c = current.Building_Height_ft__c,
				Code_Standard__c = current.Code_Standard__c,
				Existing_or_new_construction__c = current.Existing_or_new_construction__c,
				Exposure_Category__c = current.Exposure_Category__c,
				Maximum_System_Weight_Limit_lbs__c = current.Maximum_System_Weight_Limit_lbs__c,
				Module_Length_mm__c = current.Module_Length_mm__c,
				Module_Manufacturer__c = current.Module_Manufacturer__c,
				Module_Model_Number__c = current.Module_Model_Number__c,
				Module_Wattage_W__c = current.Module_Wattage_W__c,
				Module_Weight_lbs__c = current.Module_Weight_lbs__c,
				Module_Width_mm__c = current.Module_Width_mm__c,
				Panel_Orientation__c = current.Panel_Orientation__c,
				Panel_Tilt__c = current.Panel_Tilt__c,
				Parapet_Height_in__c = current.Parapet_Height_in__c,
				Parapet_Width_in__c = current.Parapet_Width_in__c,
				Planned_Install_Date__c = current.Planned_Install_Date__c,
				Point_Load_Limit_psf__c = current.Point_Load_Limit_psf__c,
				Product_Line__c = current.Product_Line__c,
				Project_Wattage_kW__c = current.Project_Wattage_kW__c,
				Risk_Category__c = current.Risk_Category__c,
				Roof_Pitch__c = current.Roof_Pitch__c,
				Roof_Surface__c = current.Roof_Surface__c,
				Setback_Distance_ft__c = current.Setback_Distance_ft__c,
				Structural_Load_Limit_psf__c = current.Structural_Load_Limit_psf__c,
				System_Configuration__c = current.System_Configuration__c,
				System_Type__c = current.System_Type__c,
				Wind_Speed_mph__c = current.Wind_Speed_mph__c
			);

			insert newRev;
			return newRev.Id;

		} catch (Exception e) {
			BoltErrorLogger.logError(
				CLASS_NAME,
				'createNewRevision',
				ERR_CREATE_NEW_REVISION + ': ' + e.getMessage(),
				e.getStackTraceString(),
				Constants.SOURCE_TYPE_APEX,
				Constants.SEVERITY_ERROR,
				UserInfo.getUserId(),
				currentRevisionId
			);
			throw e;
		}
	}
}
