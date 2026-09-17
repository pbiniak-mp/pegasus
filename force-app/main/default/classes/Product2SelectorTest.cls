@IsTest
private class Product2SelectorTest {

	private static final String EXT_ID_A = 'P2SEL-EXT-A';
	private static final String EXT_ID_B = 'P2SEL-EXT-B';
	private static final String EXT_NAME_A = 'P2SEL-NAME-A';
	private static final String EXT_NAME_B = 'P2SEL-NAME-B';

	@TestSetup
	static void setup() {
		insert new List<Product2>{
			new Product2(Name = 'Product2 Selector A', External_Id__c = EXT_ID_A, Product_Name_External__c = EXT_NAME_A, Committed__c = 5),
			new Product2(Name = 'Product2 Selector B', External_Id__c = EXT_ID_B, Product_Name_External__c = EXT_NAME_B),
			new Product2(Name = 'Product2 Selector No Keys')
		};
	}

	@IsTest
	static void testGetProductsByExternalIds_returnsMatchingProducts() {
		Test.startTest();
		List<Product2> result = Product2Selector.getProductsByExternalIds(new Set<String>{ EXT_ID_A, EXT_ID_B, 'UNKNOWN' });
		Test.stopTest();

		Assert.areEqual(2, result.size(), 'Should return only products with matching External_Id__c');
	}

	@IsTest
	static void testGetProductsByExternalIds_emptyInput_returnsEmpty() {
		Test.startTest();
		List<Product2> result = Product2Selector.getProductsByExternalIds(new Set<String>());
		Test.stopTest();

		Assert.areEqual(0, result.size());
	}

	@IsTest
	static void testGetProductByExternalId_returnsRecordWithFields() {
		Test.startTest();
		Product2 result = Product2Selector.getProductByExternalId(EXT_ID_A);
		Test.stopTest();

		Assert.areNotEqual(null, result);
		Assert.areEqual(EXT_ID_A, result.External_Id__c);
		Assert.areEqual(EXT_NAME_A, result.Product_Name_External__c);
		Assert.areEqual(5, result.Committed__c.intValue(),'Committed__c should be loaded');
	}

	@IsTest
	static void testGetProductByExternalId_unknownId_returnsNull() {
		Test.startTest();
		Product2 result = Product2Selector.getProductByExternalId('UNKNOWN');
		Test.stopTest();

		Assert.areEqual(null, result);
	}

	@IsTest
	static void testGetProductsByNameExternal_returnsMatchingProducts() {
		Test.startTest();
		List<Product2> result = Product2Selector.getProductsByNameExternal(new Set<String>{ EXT_NAME_B });
		Test.stopTest();

		Assert.areEqual(1, result.size());
		Assert.areEqual(EXT_ID_B, result[0].External_Id__c);
	}

	@IsTest
	static void testGetProductsByNameExternal_unknownName_returnsEmpty() {
		Test.startTest();
		List<Product2> result = Product2Selector.getProductsByNameExternal(new Set<String>{ 'UNKNOWN' });
		Test.stopTest();

		Assert.areEqual(0, result.size());
	}
}
