/**
 * Builds the Opportunity project code TT-PPPPP-SS-KWW-RR:
 *   TT    - Product_Line_Code__c, mapped from Product_Line__c
 *   PPPPP - Short_Project_Name__c, first 5 chars of ProjectName__c
 *   SS    - Project_State_Code__c (populated earlier by StateCodeService)
 *   KWW   - Project_Wattage_kW__c rounded to the nearest kW
 *   RR    - 'R' + Active_Revision_Number__c, mirrored from the active Design Revision
 *
 * Runs in the Opportunity before insert/update context, after StateCodeService.
 * Activating a Design Revision updates the Opportunity (DesignRevisionService),
 * so the code follows the active revision without extra wiring. The code (and
 * its segment fields) are frozen once the Opportunity is Won, so the value
 * handed to downstream systems stays stable. When any segment is missing the
 * whole code is left blank rather than emitting a partial code.
 */
public inherited sharing class ProjectCodeService {

	/**
	 * Populates Product_Line_Code__c, Short_Project_Name__c and Project_Code__c
	 * on the given Opportunities. Call from before insert (oldMap = null) and
	 * before update. Product_Line_Code__c is always re-derived from
	 * Product_Line__c, so any manual edit is overwritten on save.
	 *
	 * @param newList the Opportunities being inserted/updated (Trigger.new)
	 * @param oldMap the pre-update Opportunity state keyed by Id, or null on insert (Trigger.oldMap)
	 */
	public static void apply(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
		if (newList == null || newList.isEmpty()) return;

		for (Opportunity opp : newList) {
			Opportunity oldOpp = oldMap == null ? null : oldMap.get(opp.Id);
			if (isFrozen(oldOpp)) continue;

			opp.Product_Line_Code__c = getProductLineCode(opp.Product_Line__c);

			// A manually entered short name is kept, but a new project name (e.g.
			// mirrored from a newly activated Design Revision) re-derives it.
			Boolean projectNameChanged = oldOpp != null && oldOpp.ProjectName__c != opp.ProjectName__c;
			if (String.isBlank(opp.Short_Project_Name__c) || projectNameChanged) {
				opp.Short_Project_Name__c = getShortName(opp.ProjectName__c);
			}

			opp.Project_Code__c = buildCode(
				opp.Product_Line_Code__c,
				opp.Short_Project_Name__c,
				opp.Project_State_Code__c,
				opp.Project_Wattage_kW__c,
				opp.Active_Revision_Number__c
			);
		}
	}

	/**
	 * Maps a Product Line to its TT acronym (Product_Line_Code__c).
	 *
	 * @param productLine the Product_Line__c picklist value
	 * @return the mapped acronym, or null when the value is blank or unmapped
	 */
	public static String getProductLineCode(String productLine) {
		if (String.isBlank(productLine)) return null;
		return Constants.PRODUCT_LINE_TO_CODE.get(productLine);
	}

	/**
	 * Builds the PPPPP segment: all whitespace removed, uppercased, first N
	 * characters. E.g. "TE 30 AA" -> "TE30A".
	 *
	 * @param projectName the ProjectName__c value
	 * @return the shortened name, or null when the value is blank
	 */
	public static String getShortName(String projectName) {
		if (String.isBlank(projectName)) return null;
		String compact = projectName.replaceAll('\\s+', '');
		if (String.isEmpty(compact)) return null;
		Integer len = Math.min(compact.length(), Constants.PROJECT_SHORT_NAME_LENGTH);
		return compact.substring(0, len).toUpperCase();
	}

	/**
	 * Assembles the full project code TT-PPPPP-SS-KWW-RR.
	 *
	 * @param productLineCode the product line acronym (Product_Line_Code__c)
	 * @param ppppp the short project name (Short_Project_Name__c)
	 * @param ss the state code (Project_State_Code__c)
	 * @param wattageKw the project wattage in kW; rounded HALF_UP for the KWW segment
	 * @param revisionNumber the active Design Revision number (Active_Revision_Number__c); prefixed with 'R'
	 * @return the assembled code, or null when any segment is missing (wattage null or non-positive counts as missing)
	 */
	public static String buildCode(
		String productLineCode,
		String ppppp,
		String ss,
		Decimal wattageKw,
		String revisionNumber
	) {
		if (String.isBlank(productLineCode) || String.isBlank(ppppp) || String.isBlank(ss) || String.isBlank(revisionNumber)) {
			return null;
		}
		if (wattageKw == null || wattageKw <= 0) return null;

		String kww = String.valueOf(wattageKw.round(System.RoundingMode.HALF_UP));
		String rr = Constants.PROJECT_CODE_REVISION_PREFIX + revisionNumber.trim().toUpperCase();
		return String.join(
			new List<String>{ productLineCode, ppppp, ss, kww, rr },
			Constants.PROJECT_CODE_SEGMENT_SEPARATOR
		);
	}

	/**
	 * The code and its segments are frozen once the Opportunity has been Won.
	 *
	 * @param oldOpp the pre-update Opportunity state, or null on insert
	 * @return true when the record was already Won before this save
	 */
	private static Boolean isFrozen(Opportunity oldOpp) {
		return oldOpp != null && oldOpp.IsWon;
	}
}
