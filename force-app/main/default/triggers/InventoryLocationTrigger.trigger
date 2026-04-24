trigger InventoryLocationTrigger on Inventory_Location__c(before insert, before update, before delete, after insert, after update, after delete, after undelete) {
	new InventoryLocationTriggerHandler().run();
}
