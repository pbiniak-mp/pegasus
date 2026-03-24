public virtual class TriggerHandler {
	private static final Set<SObjectType> allowedCommunityApiObjects = new Set<SObjectType>{ ContentVersion.SObjectType };

	private static final Map<String, LoopCount> loopCountMap;
	private static final Set<String> bypassedHandlers;

	public static Boolean firstRun;
	public static Boolean avoidChainAsync;
	public static Boolean bypassAllTriggers = false;
	public static Boolean firstRunOfAllTriggersInTransaction = true;

	@TestVisible
	protected TriggerContext context;

	@TestVisible
	private Boolean isTriggerExecuting;

	static {
		loopCountMap = new Map<String, LoopCount>();
		bypassedHandlers = new Set<String>();
		firstRun = true;
		avoidChainAsync = false;
	}

	public TriggerHandler() {
		this.setTriggerContext();
	}

	public void run() {
		if (!validateRun()) return;

		addToLoopCount();

		if (this.context == TriggerContext.BEFORE_INSERT) {
			this.beforeInsert();
		} else if (this.context == TriggerContext.BEFORE_UPDATE) {
			this.beforeUpdate();
		} else if (this.context == TriggerContext.BEFORE_DELETE) {
			this.beforeDelete();
		} else if (this.context == TriggerContext.AFTER_INSERT) {
			this.afterInsert();
		} else if (this.context == TriggerContext.AFTER_UPDATE) {
			this.afterUpdate();
		} else if (this.context == TriggerContext.AFTER_DELETE) {
			this.afterDelete();
		} else if (this.context == TriggerContext.AFTER_UNDELETE) {
			this.afterUndelete();
		}
	}

	public void setMaxLoopCount(Integer max) {
		String handlerName = getHandlerName();
		if (!TriggerHandler.loopCountMap.containsKey(handlerName)) {
			TriggerHandler.loopCountMap.put(handlerName, new LoopCount(max));
		} else {
			TriggerHandler.loopCountMap.get(handlerName).setMax(max);
		}
	}

	public void clearMaxLoopCount() {
		this.setMaxLoopCount(-1);
	}

	public static void bypass(String handlerName) {
		TriggerHandler.bypassedHandlers.add(handlerName);
	}

	public static void clearBypass(String handlerName) {
		TriggerHandler.bypassedHandlers.remove(handlerName);
	}

	public static Boolean isBypassed(String handlerName) {
		return TriggerHandler.bypassedHandlers.contains(handlerName);
	}

	public static void clearAllBypasses() {
		TriggerHandler.bypassedHandlers.clear();
	}

	@TestVisible
	private void setTriggerContext() {
		this.setTriggerContext(null, false);
	}

	@TestVisible
	private void setTriggerContext(String ctx, Boolean testMode) {
		if (!Trigger.isExecuting && !testMode) {
			this.isTriggerExecuting = false;
			return;
		} else {
			this.isTriggerExecuting = true;
		}

		if (
			(Trigger.isExecuting && Trigger.isBefore && Trigger.isInsert) ||
			(ctx != null && ctx == 'before insert')
		) {
			this.context = TriggerContext.BEFORE_INSERT;
		} else if (
			(Trigger.isExecuting && Trigger.isBefore && Trigger.isUpdate) ||
			(ctx != null && ctx == 'before update')
		) {
			this.context = TriggerContext.BEFORE_UPDATE;
		} else if (
			(Trigger.isExecuting && Trigger.isBefore && Trigger.isDelete) ||
			(ctx != null && ctx == 'before delete')
		) {
			this.context = TriggerContext.BEFORE_DELETE;
		} else if (
			(Trigger.isExecuting && Trigger.isAfter && Trigger.isInsert) ||
			(ctx != null && ctx == 'after insert')
		) {
			this.context = TriggerContext.AFTER_INSERT;
		} else if (
			(Trigger.isExecuting && Trigger.isAfter && Trigger.isUpdate) ||
			(ctx != null && ctx == 'after update')
		) {
			this.context = TriggerContext.AFTER_UPDATE;
		} else if (
			(Trigger.isExecuting && Trigger.isAfter && Trigger.isDelete) ||
			(ctx != null && ctx == 'after delete')
		) {
			this.context = TriggerContext.AFTER_DELETE;
		} else if (
			(Trigger.isExecuting && Trigger.isAfter && Trigger.isUndelete) ||
			(ctx != null && ctx == 'after undelete')
		) {
			this.context = TriggerContext.AFTER_UNDELETE;
		}
	}

	@TestVisible
	private void addToLoopCount() {
		String handlerName = getHandlerName();
		if (TriggerHandler.loopCountMap.containsKey(handlerName)) {
			Boolean exceeded = TriggerHandler.loopCountMap.get(handlerName).increment();
			if (TriggerHandler.loopCountMap.get(handlerName).count > 1) firstRun = false;
			if (exceeded) {
				Integer max = TriggerHandler.loopCountMap.get(handlerName).max;
				throw new TriggerHandlerException(
					'Maximum loop count of ' + String.valueOf(max) + ' reached in ' + handlerName
				);
			}
		}
	}

	@TestVisible
	private Boolean validateRun() {
		if (!this.isTriggerExecuting || this.context == null) {
			throw new TriggerHandlerException('Trigger handler called outside of Trigger execution');
		}

		if (TriggerHandler.bypassedHandlers.contains(getHandlerName()) || TriggerHandler.bypassAllTriggers) {
			return false;
		}

		if (TriggerHandler.firstRunOfAllTriggersInTransaction) {
			TriggerHandler.firstRunOfAllTriggersInTransaction = false;
			SObjectType sObjectType = Trigger.isDelete ? Trigger.old.getSObjectType() : Trigger.new.getSObjectType();
		}

		return true;
	}

	@TestVisible
	private String getHandlerName() {
		return String.valueOf(this).substring(0, String.valueOf(this).indexOf(':'));
	}

	@TestVisible
	protected virtual void beforeInsert() {
	}
	@TestVisible
	protected virtual void beforeUpdate() {
	}
	@TestVisible
	protected virtual void beforeDelete() {
	}
	@TestVisible
	protected virtual void afterInsert() {
	}
	@TestVisible
	protected virtual void afterUpdate() {
	}
	@TestVisible
	protected virtual void afterDelete() {
	}
	@TestVisible
	protected virtual void afterUndelete() {
	}

	@TestVisible
	private class LoopCount {
		private Integer max;
		private Integer count;

		public LoopCount() {
			this.max = 5;
			this.count = 0;
		}

		public LoopCount(Integer max) {
			this.max = max;
			this.count = 0;
		}

		public Boolean increment() {
			this.count++;
			return this.exceeded();
		}

		public Boolean exceeded() {
			if (this.max < 0) return false;
			if (this.count > this.max) return true;
			return false;
		}

		public Integer getMax() {
			return this.max;
		}

		public Integer getCount() {
			return this.count;
		}

		public void setMax(Integer max) {
			this.max = max;
		}
	}

	@TestVisible
	private enum TriggerContext {
		BEFORE_INSERT,
		BEFORE_UPDATE,
		BEFORE_DELETE,
		AFTER_INSERT,
		AFTER_UPDATE,
		AFTER_DELETE,
		AFTER_UNDELETE
	}

	public class TriggerHandlerException extends Exception {
	}

	private static Boolean wasRunFromApiCommunity() {
		if (Test.isRunningTest() || UserInfo.getName().contains('Site Guest User')) {
			return false;
		}
		String sessionType = Auth.SessionManagement.getCurrentSession()?.get('SessionType');
		String loginType = !Test.isRunningTest() ? sessionType : 'Test';
		return loginType == 'ChatterNetworksAPIOnly';
	}
}
