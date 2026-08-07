/**
 * Builds the Opportunity project code CCC-TT-PPPPP-RR-SS-KWW:
 *   CCC   - Account.Naming_Acronym__c of the Opportunity's Account
 *   TT    - Product_Line_Code__c, mapped from Product_Line__c
 *   PPPPP - Short_Project_Name__c, first 5 alphanumerics of ProjectName__c
 *   RR    - Active_Revision_Number__c, mirrored from the active Design Revision
 *   SS    - Project_State_Code__c (populated earlier by StateCodeService)
 *   KWW   - Project_Wattage_kW__c rounded to the nearest kW
 *
 * Runs in the Opportunity before insert/update context, after StateCodeService.
 * Activating a Design Revision updates the Opportunity (DesignRevisionService),
 * so the code follows the active revision without extra wiring. The customer
 * acronym is read live from the Account, so changing it there only reaches an
 * Opportunity on its next save (or through the backfill script). The code is
 * frozen once the Opportunity is Won, so the value handed to downstream systems
 * stays stable. When any segment is missing the whole code is left blank rather
 * than emitting a partial code. Every free-text segment is stripped of
 * non-alphanumerics, so the separator can only ever appear between segments.
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

		Map<Id, String> acronymByAccountId = getNamingAcronyms(newList, oldMap);

		for (Opportunity opp : newList) {
			Opportunity oldOpp = oldMap == null ? null : oldMap.get(opp.Id);
			if (isFrozen(oldOpp)) continue;

			opp.Product_Line_Code__c = getProductLineCode(opp.Product_Line__c);

			// A manually entered short name is kept (normalised only), but a new
			// project name - e.g. mirrored from a newly activated Design Revision -
			// re-derives it.
			Boolean projectNameChanged = oldOpp != null && oldOpp.ProjectName__c != opp.ProjectName__c;
			opp.Short_Project_Name__c = String.isBlank(opp.Short_Project_Name__c) || projectNameChanged
				? getShortName(opp.ProjectName__c)
				: getShortName(opp.Short_Project_Name__c);

			opp.Project_Code__c = buildCode(
				acronymByAccountId.get(opp.AccountId),
				opp.Product_Line_Code__c,
				opp.Short_Project_Name__c,
				opp.Active_Revision_Number__c,
				opp.Project_State_Code__c,
				opp.Project_Wattage_kW__c
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
	 * Builds the PPPPP segment: everything that is not a letter or a digit is
	 * removed, then uppercased and cut to the first N characters.
	 * E.g. "ST. Lukes United Meth Ch" -> "STLUK", "TE 30 AA" -> "TE30A".
	 * Running it over an already shortened value is a no-op, so it doubles as
	 * the normaliser for a manually entered Short_Project_Name__c.
	 *
	 * @param projectName the ProjectName__c value (or an existing short name)
	 * @return the shortened name, or null when nothing alphanumeric is left
	 */
	public static String getShortName(String projectName) {
		String compact = sanitize(projectName);
		if (compact == null) return null;
		Integer len = Math.min(compact.length(), Constants.PROJECT_SHORT_NAME_LENGTH);
		return compact.substring(0, len);
	}

	/**
	 * Assembles the full project code CCC-TT-PPPPP-RR-SS-KWW.
	 *
	 * @param customerCode the customer acronym (Account.Naming_Acronym__c)
	 * @param productLineCode the product line acronym (Product_Line_Code__c)
	 * @param ppppp the short project name (Short_Project_Name__c)
	 * @param revisionNumber the active Design Revision number (Active_Revision_Number__c)
	 * @param ss the state code (Project_State_Code__c)
	 * @param wattageKw the project wattage in kW; rounded HALF_UP for the KWW segment
	 * @return the assembled code, or null when any segment is missing (wattage null or non-positive counts as missing)
	 */
	public static String buildCode(
		String customerCode,
		String productLineCode,
		String ppppp,
		String revisionNumber,
		String ss,
		Decimal wattageKw
	) {
		String ccc = sanitize(customerCode);
		String tt = sanitize(productLineCode);
		String name = sanitize(ppppp);
		String rr = sanitize(revisionNumber);
		String state = sanitize(ss);

		if (ccc == null || tt == null || name == null || rr == null || state == null) return null;
		if (wattageKw == null || wattageKw <= 0) return null;

		String kww = String.valueOf(wattageKw.round(System.RoundingMode.HALF_UP));
		return String.join(
			new List<String>{ ccc, tt, name, rr, state, kww },
			Constants.PROJECT_CODE_SEGMENT_SEPARATOR
		);
	}

	/**
	 * Strips every non-alphanumeric character and uppercases what is left, so a
	 * segment can never carry a separator, a dot or an underscore into the code.
	 *
	 * @param value the raw segment value
	 * @return the cleaned value, or null when nothing alphanumeric is left
	 */
	private static String sanitize(String value) {
		if (String.isBlank(value)) return null;
		String cleaned = value.replaceAll(Constants.PROJECT_CODE_INVALID_CHARS, '');
		return String.isEmpty(cleaned) ? null : cleaned.toUpperCase();
	}

	/**
	 * Reads the customer acronym for every Account behind an Opportunity that is
	 * still being (re)coded. One query per trigger context; frozen records are
	 * skipped because their code is not rebuilt anyway.
	 *
	 * @param newList the Opportunities being inserted/updated
	 * @param oldMap the pre-update Opportunity state keyed by Id, or null on insert
	 * @return Naming_Acronym__c keyed by Account Id
	 */
	private static Map<Id, String> getNamingAcronyms(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
		Set<Id> accountIds = new Set<Id>();
		for (Opportunity opp : newList) {
			Opportunity oldOpp = oldMap == null ? null : oldMap.get(opp.Id);
			if (isFrozen(oldOpp) || opp.AccountId == null) continue;
			accountIds.add(opp.AccountId);
		}

		Map<Id, String> acronymByAccountId = new Map<Id, String>();
		if (accountIds.isEmpty()) return acronymByAccountId;

		for (Account acc : AccountSelector.getNamingAcronymsByIds(accountIds)) {
			acronymByAccountId.put(acc.Id, acc.Naming_Acronym__c);
		}
		return acronymByAccountId;
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
