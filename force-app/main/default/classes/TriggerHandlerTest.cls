@IsTest
private class TriggerHandlerTest {

	// Concrete subclass used to spy on which context methods fire
	private class TestHandler extends TriggerHandler {
		public Boolean beforeInsertFired  = false;
		public Boolean beforeUpdateFired  = false;
		public Boolean beforeDeleteFired  = false;
		public Boolean afterInsertFired   = false;
		public Boolean afterUpdateFired   = false;
		public Boolean afterDeleteFired   = false;
		public Boolean afterUndeleteFired = false;

		public override void beforeInsert()  { beforeInsertFired  = true; }
		public override void beforeUpdate()  { beforeUpdateFired  = true; }
		public override void beforeDelete()  { beforeDeleteFired  = true; }
		public override void afterInsert()   { afterInsertFired   = true; }
		public override void afterUpdate()   { afterUpdateFired   = true; }
		public override void afterDelete()   { afterDeleteFired   = true; }
		public override void afterUndelete() { afterUndeleteFired = true; }
	}

	// Builds a handler set to a specific context in testMode.
	// firstRunOfAllTriggersInTransaction is pre-cleared to avoid Trigger.new NPE.
	private static TestHandler makeHandler(String ctx) {
		TriggerHandler.firstRunOfAllTriggersInTransaction = false;
		TestHandler h = new TestHandler();
		h.setTriggerContext(ctx, true);
		return h;
	}

	@IsTest
	static void testRunOutsideTrigger_throwsException() {
		try {
			new TestHandler().run();
			Assert.fail('Expected TriggerHandlerException');
		} catch (TriggerHandler.TriggerHandlerException e) {
			Assert.isTrue(e.getMessage().contains('called outside of Trigger execution'));
		}
	}

	@IsTest
	static void testBypass_isBypassed_clearBypass() {
		TriggerHandler.bypass('SomeHandler');
		Assert.isTrue(TriggerHandler.isBypassed('SomeHandler'));
		TriggerHandler.clearBypass('SomeHandler');
		Assert.isFalse(TriggerHandler.isBypassed('SomeHandler'));
	}

	@IsTest
	static void testClearAllBypasses() {
		TriggerHandler.bypass('HandlerA');
		TriggerHandler.bypass('HandlerB');
		TriggerHandler.clearAllBypasses();
		Assert.isFalse(TriggerHandler.isBypassed('HandlerA'));
		Assert.isFalse(TriggerHandler.isBypassed('HandlerB'));
	}

	@IsTest
	static void testIsBypassed_returnsFalse_forUnknownHandler() {
		Assert.isFalse(TriggerHandler.isBypassed('NonExistentHandler'));
	}

	@IsTest
	static void testBypassAllTriggers_preventsDispatch() {
		TriggerHandler.bypassAllTriggers = true;
		TestHandler h = makeHandler('before insert');
		h.run();
		Assert.isFalse(h.beforeInsertFired, 'bypassAllTriggers should prevent dispatch');
		TriggerHandler.bypassAllTriggers = false;
	}

	@IsTest
	static void testBeforeInsert_dispatches() {
		TestHandler h = makeHandler('before insert');
		h.run();
		Assert.isTrue(h.beforeInsertFired);
		Assert.isFalse(h.afterInsertFired);
	}

	@IsTest
	static void testBeforeUpdate_dispatches() {
		TestHandler h = makeHandler('before update');
		h.run();
		Assert.isTrue(h.beforeUpdateFired);
	}

	@IsTest
	static void testBeforeDelete_dispatches() {
		TestHandler h = makeHandler('before delete');
		h.run();
		Assert.isTrue(h.beforeDeleteFired);
	}

	@IsTest
	static void testAfterInsert_dispatches() {
		TestHandler h = makeHandler('after insert');
		h.run();
		Assert.isTrue(h.afterInsertFired);
	}

	@IsTest
	static void testAfterUpdate_dispatches() {
		TestHandler h = makeHandler('after update');
		h.run();
		Assert.isTrue(h.afterUpdateFired);
	}

	@IsTest
	static void testAfterDelete_dispatches() {
		TestHandler h = makeHandler('after delete');
		h.run();
		Assert.isTrue(h.afterDeleteFired);
	}

	@IsTest
	static void testAfterUndelete_dispatches() {
		TestHandler h = makeHandler('after undelete');
		h.run();
		Assert.isTrue(h.afterUndeleteFired);
	}

	@IsTest
	static void testMaxLoopCount_exceeded_throwsException() {
		TestHandler h = makeHandler('before insert');
		h.setMaxLoopCount(1);
		h.run(); // count = 1, max = 1 → OK (exceeded = count > max = 1 > 1 = false)
		try {
			h.run(); // count = 2 > 1 → throws
			Assert.fail('Expected TriggerHandlerException for loop count exceeded');
		} catch (TriggerHandler.TriggerHandlerException e) {
			Assert.isTrue(e.getMessage().contains('Maximum loop count'));
		}
	}

	@IsTest
	static void testClearMaxLoopCount_allowsUnlimitedRuns() {
		TestHandler h = makeHandler('before insert');
		h.setMaxLoopCount(1);
		h.clearMaxLoopCount(); // sets max to -1 → exceeded() always false
		h.run();
		h.run();
		Assert.isTrue(h.beforeInsertFired, 'Multiple runs should be allowed after clearMaxLoopCount');
	}
}
