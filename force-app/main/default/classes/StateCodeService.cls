/**
 * Maps state/province names to ISO codes for the Opportunity Project Address.
 * Covers US states/territories and Canadian provinces; extend the map when
 * projects appear in a new country.
 */
public inherited sharing class StateCodeService {

	private static final Map<String, String> STATE_NAME_TO_CODE = new Map<String, String>{
		'alabama' => 'AL',
		'alaska' => 'AK',
		'arizona' => 'AZ',
		'arkansas' => 'AR',
		'california' => 'CA',
		'colorado' => 'CO',
		'connecticut' => 'CT',
		'delaware' => 'DE',
		'district of columbia' => 'DC',
		'florida' => 'FL',
		'georgia' => 'GA',
		'hawaii' => 'HI',
		'idaho' => 'ID',
		'illinois' => 'IL',
		'indiana' => 'IN',
		'iowa' => 'IA',
		'kansas' => 'KS',
		'kentucky' => 'KY',
		'louisiana' => 'LA',
		'maine' => 'ME',
		'maryland' => 'MD',
		'massachusetts' => 'MA',
		'michigan' => 'MI',
		'minnesota' => 'MN',
		'mississippi' => 'MS',
		'missouri' => 'MO',
		'montana' => 'MT',
		'nebraska' => 'NE',
		'nevada' => 'NV',
		'new hampshire' => 'NH',
		'new jersey' => 'NJ',
		'new mexico' => 'NM',
		'new york' => 'NY',
		'north carolina' => 'NC',
		'north dakota' => 'ND',
		'ohio' => 'OH',
		'oklahoma' => 'OK',
		'oregon' => 'OR',
		'pennsylvania' => 'PA',
		'rhode island' => 'RI',
		'south carolina' => 'SC',
		'south dakota' => 'SD',
		'tennessee' => 'TN',
		'texas' => 'TX',
		'utah' => 'UT',
		'vermont' => 'VT',
		'virginia' => 'VA',
		'washington' => 'WA',
		'west virginia' => 'WV',
		'wisconsin' => 'WI',
		'wyoming' => 'WY',
		'american samoa' => 'AS',
		'guam' => 'GU',
		'northern mariana islands' => 'MP',
		'puerto rico' => 'PR',
		'u.s. virgin islands' => 'VI',
		'united states minor outlying islands' => 'UM',
		'armed forces americas' => 'AA',
		'armed forces europe' => 'AE',
		'armed forces pacific' => 'AP',
		'alberta' => 'AB',
		'british columbia' => 'BC',
		'manitoba' => 'MB',
		'new brunswick' => 'NB',
		'newfoundland and labrador' => 'NL',
		'northwest territories' => 'NT',
		'nova scotia' => 'NS',
		'nunavut' => 'NU',
		'ontario' => 'ON',
		'prince edward island' => 'PE',
		'quebec' => 'QC',
		'saskatchewan' => 'SK',
		'yukon' => 'YT'
	};

	/** Returns the ISO code for a state/province name, or null when unknown. */
	public static String getCode(String stateName) {
		if (String.isBlank(stateName)) return null;
		return STATE_NAME_TO_CODE.get(stateName.trim().toLowerCase());
	}

	/**
	 * Before insert/update: keeps Project_State_Code__c in sync with
	 * Project_State__c. A code set explicitly in the same DML (e.g. by
	 * LeadService, which copies the authoritative Lead.StateCode) wins.
	 */
	public static void applyProjectStateCodes(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
		for (Opportunity opp : newList) {
			Opportunity oldOpp = oldMap == null ? null : oldMap.get(opp.Id);
			Boolean stateChanged = oldOpp == null || opp.Project_State__c != oldOpp.Project_State__c;
			Boolean codeChanged = oldOpp == null
				? opp.Project_State_Code__c != null
				: opp.Project_State_Code__c != oldOpp.Project_State_Code__c;
			if (!stateChanged || codeChanged) continue;
			opp.Project_State_Code__c = getCode(opp.Project_State__c);
		}
	}
}
