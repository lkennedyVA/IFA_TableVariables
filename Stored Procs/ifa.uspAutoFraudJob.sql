USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspAutoFraudJob
	Description: This procedure creates/deactivates AutoFraud records based on the 
		AutoFraudTypes defined.

	Tables: [ifa].[AutoFraudType]
		,[ifa].[AutoFraud]
		,[ifa].[AutoFraudJob]

	Function: [stat].[ufnAutoJobStat]
	History:
		2020-12-14 - LBD - Recreated, added logging 
		2025-01-09 - LXK - Replaced table variables with local temp tables, added temp table indexes and drop tables at the ending
*****************************************************************************************/
ALTER   PROCEDURE [ifa].[uspAutoFraudJob](
	@pdtNow DATETIME2(7) = NULL
)AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @iLogLevel int = ISNULL(TRY_CONVERT(INT,[common].[ufnConfigValue](N'LogLevel [ifa].[uspAutoFraudJob]')),1)	
		,@ncProcessKey nchar(25) = REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(50),sysdatetime(),121),'-',''),' ',''),':',''),'.','')
		,@dtNow datetime2(7) = ISNULL(@pdtNow,SYSDATETIME())
		,@dtTimerDate datetime2(7) = SYSDATETIME()
		,@dtInitial datetime2(7) = SYSDATETIME() --used for complete time in procedure
		,@ncSchemaName nchar(20) = CONVERT(nchar(20),OBJECT_SCHEMA_NAME(@@PROCID))
		,@ncObjectName nchar(50) = CONVERT(nchar(50),OBJECT_NAME(@@PROCID))
		,@iRowCnt int;

	drop table if exists #AutoFraudType
	create table #AutoFraudType(
		 AutoFraudTypeId int primary key
		,Code nvarchar(25)
		,[Name] nvarchar(50)
		,Descr nvarchar(255)
		,DisplayOrder int
		,FreqInHours decimal(4, 2)
		,KeyIdType nvarchar(25)
		,DateExpiredDays int
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100) 
	);

	drop table if exists #AutoFraud
	create table #AutoFraud(
		 AutoFraudId bigint
		,AutoFraudTypeId int
		,OrgId int
		,KeyId bigint
		,StatusFlag int
		,DateActivated datetime2(7)
		,DateExpired datetime2(7)
		,UserName nvarchar(100)
	);

	drop table if exists #AutoFraudJob
	create table #AutoFraudJob(
		 AutoFraudJobId int
		,AutoFraudTypeId int
		,DateLastExecuted datetime2(7)
		,StatusFlag int
		,DateActivated datetime2(7)
	);

	drop table if exists #RunMe
	create table #RunMe(
		 AutoFraudJobId int 
		,AutoFraudTypeId int
		,AutoFraudTypeCode nvarchar(25)
		,StartDate datetime2(7)
		,EndDate datetime2(7)
	);

	drop table if exists #AL
	create table #AL(
		 AutoFraudTypeId int
		,OrgId int
		,KeyId bigint
	);

	drop table if exists #DAL
	create table #DAL(
		AutoFraudId int
	);
CREATE INDEX IX_AutoFraud_TypeId ON #AutoFraud(AutoFraudTypeId);
CREATE INDEX IX_AutoFraud_OrgId ON #AutoFraud(OrgId);
CREATE INDEX IX_AutoFraudJob_TypeId ON #AutoFraudJob(AutoFraudTypeId);
CREATE CLUSTERED INDEX IX_RunMe_TypeId ON #RunMe(AutoFraudTypeId);
CREATE NONCLUSTERED INDEX IX_AL_OrgId ON #AL(OrgId);

	IF @iLogLevel > 0
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Enter' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
		SET @dtTimerDate  = SYSDATETIME();
	END

	--LOAD REFERENCE TABLES
	INSERT INTO #AutoFraudType(AutoFraudTypeId,Code,Name,Descr,DisplayOrder,FreqInHours
		,KeyIdType,DateExpiredDays,StatusFlag,DateActivated,UserName)
	SELECT AutoFraudTypeId,Code,Name,Descr,DisplayOrder,FreqInHours
		,KeyIdType,DateExpiredDays,StatusFlag,DateActivated,UserName
	FROM [ifa].[AutoFraudType] 
	WHERE StatusFlag = 1;

	INSERT INTO #AutoFraudJob(AutoFraudJobId,AutoFraudTypeId,DateLastExecuted,StatusFlag,DateActivated)
	SELECT afj.AutoFraudJobId,aft.AutoFraudTypeId,afj.DateLastExecuted,afj.StatusFlag,afj.DateActivated
	FROM #AutoFraudType aft
	LEFT OUTER JOIN [ifa].[AutoFraudJob] afj  ON aft.AutoFraudTypeId = afj.AutoFraudTypeId
	WHERE aft.StatusFlag = 1;

	IF EXISTS (SELECT 'X' FROM #AutoFraudJob WHERE ISNULL(AutoFraudJobId,-1) = -1)
	BEGIN
		--INSERT any new jobs 
		INSERT INTO [ifa].[AutoFraudJob](AutoFraudTypeId, DateLastExecuted, StatusFlag, DateActivated)
			OUTPUT inserted.AutoFraudJobId
				,inserted.AutoFraudTypeId
				,inserted.DateLastExecuted
				,inserted.StatusFlag
				,inserted.DateActivated
			INTO #AutoFraudJob
		SELECT afj.AutoFraudTypeId, DATEADD(MINUTE,(aft.FreqInHours*-60.0),@dtNow), 1, @dtNow
		FROM #AutoFraudJob afj
		INNER JOIN #AutoFraudType aft ON afj.AutoFraudTypeId = aft.AutoFraudTypeId
		WHERE ISNULL(AutoFraudJobId,-1) = -1;
		DELETE FROM #AutoFraudJob WHERE ISNULL(AutoFraudJobId,-1) = -1;
	END

	IF @iLogLevel > 1
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Insert New Jobs' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
		SET @dtTimerDate  = SYSDATETIME();
	END

	--ARE there any ready for the next run?
	INSERT INTO #RunMe(AutoFraudJobId,AutoFraudTypeId,AutoFraudTypeCode,StartDate,EndDate)
	SELECT alj.AutoFraudJobId
		,alt.AutoFraudTypeId,alt.Code
		,DATEADD(MINUTE,(FreqInHours*-60.0)-1,@dtNow)
		,DATEADD(MINUTE,-1,@dtNow)
	FROM #AutoFraudType alt
	LEFT JOIN #AutoFraudJob alj on alt.AutoFraudTypeId = alj.AutoFraudTypeId 
	WHERE DATEADD(MINUTE,(FreqInHours*60.0)-1,alj.DateLastExecuted) <= @dtNow;

	IF @iLogLevel > 1
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load RunMe' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
		SET @dtTimerDate  = SYSDATETIME();
	END

	--ANY TO Deactivate?
	INSERT INTO #DAL(AutoFraudId)
	SELECT AutoFraudId
	FROM [ifa].[AutoFraud] 
	WHERE DateExpired <= @dtNow
		AND StatusFlag = 1;

	IF EXISTS (SELECT 'X' FROM #RunMe)
	BEGIN
		OPEN SYMMETRIC KEY VALIdSymKey DECRYPTION BY ASYMMETRIC KEY [VALIDASYMKEY]; 
		--GENERATE any that are timely
		IF EXISTS (SELECT 'X' FROM #RunMe WHERE AutoFraudTypeCode = 'CFD1000')
			INSERT INTO #AL(KeyId, OrgId, AutoFraudTypeId)
			SELECT DISTINCT CustomerId, ClientOrgId, AutoFraudTypeId
			FROM (SELECT p.CustomerId, [common].[ufnOrgClientId](p.OrgId) as ClientOrgId, [common].[ufnOrgChannelId](p.OrgId) as Channel, rm.AutoFraudTypeId,
						ISNULL(ajs.PayerClearedItemCount,0) AS PayerClearedItemCount
				FROM  [ifa].[Item] i WITH (READUNCOMMITTED)
				INNER JOIN [ifa].[Process] p WITH (READUNCOMMITTED) on i.ProcessId = p.ProcessId
				INNER JOIN [payer].[Payer] pa WITH (READUNCOMMITTED) on i.PayerId = pa.PayerId
				CROSS APPLY #RunMe rm
				OUTER APPLY [stat].[ufnAutoJobStat](i.PayerId,p.CustomerId) ajs 
				WHERE i.DateActivated BETWEEN rm.StartDate AND rm.EndDate
					AND ISNULL(TRY_CONVERT(BIGINT,i.CheckNumber),0) BETWEEN 1 AND 350
					AND i.CheckAmount > 500 
					AND [common].[ufnOnUs]([common].[ufnOrgClientId](p.OrgId),pa.RoutingNumber,pa.AccountNumber) = 0
					AND rm.AutoFraudTypeCode = 'CFD1000'
					) as chnl
			WHERE chnl.Channel in (1,2,3)
				AND chnl.PayerClearedItemCount = 0;

		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load CFD1000' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @dtTimerDate  = SYSDATETIME();
		END

		IF EXISTS (SELECT 'X' FROM #RunMe WHERE AutoFraudTypeCode = 'CFD1100')
			INSERT INTO #AL(KeyId, OrgId, AutoFraudTypeId)
			SELECT DISTINCT CustomerId, ClientOrgId, AutoFraudTypeId
			FROM (SELECT p.CustomerId, [common].[ufnOrgClientId](p.OrgId) as ClientOrgId, rm.AutoFraudTypeId
				FROM  [ifa].[Item] i WITH (READUNCOMMITTED)
				INNER JOIN [ifa].[Process] p WITH (READUNCOMMITTED) on i.ProcessId = p.ProcessId
				INNER JOIN [payer].[Payer] pa WITH (READUNCOMMITTED) on i.PayerId = pa.PayerId
				CROSS APPLY #RunMe rm 
				WHERE i.DateActivated BETWEEN rm.StartDate AND rm.EndDate
					AND pa.RoutingNumber = '000000518'
					AND (
							(LEN(i.CheckNumber) = 8
								AND (ISNULL(TRY_CONVERT(BIGINT,i.CheckNumber),0)%11) not in (0,10)
							)
						or
							(LEN(i.CheckNumber) = 9
								AND ((ISNULL(TRY_CONVERT(BIGINT,i.CheckNumber),0)%10) - (ISNULL(TRY_CONVERT(INT,SUBSTRING(i.CheckNumber,1,8)),0) %11)
									) <> 0
							)
						)
					AND rm.AutoFraudTypeCode = 'CFD1100') as ust;

		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load CFD1100' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @dtTimerDate  = SYSDATETIME();
		END

		IF EXISTS (SELECT 'X' FROM #RunMe WHERE AutoFraudTypeCode = 'CFD1200')
			INSERT INTO #AL(KeyId, OrgId, AutoFraudTypeId)
			SELECT DISTINCT CustomerId, ClientOrgId, AutoFraudTypeId
			FROM (SELECT p.CustomerId, [common].[ufnOrgClientId](p.OrgId) as ClientOrgId, [common].[ufnOrgChannelId](p.OrgId) as Channel, rm.AutoFraudTypeId
					FROM  [ifa].[Item] i WITH (READUNCOMMITTED)
					INNER JOIN [ifa].[Process] p WITH (READUNCOMMITTED) on i.ProcessId = p.ProcessId
					INNER JOIN [payer].[Payer] pa WITH (READUNCOMMITTED) on i.PayerId = pa.PayerId
					CROSS APPLY [stat].[ufnAutoJobStat](i.PayerId,p.CustomerId) ajs
					CROSS APPLY #RunMe rm 
					WHERE i.DateActivated BETWEEN rm.StartDate AND rm.EndDate
						AND ajs.CustClearedItemCount = 0
						AND DATEDIFF(DAY,ajs.CustOpenDate,GETDATE()) > 90
						AND i.CheckAmount > 100 
						AND [common].[ufnOnUs]([common].[ufnOrgClientId](p.OrgId),pa.RoutingNumber,pa.AccountNumber) = 0
						AND rm.AutoFraudTypeCode = 'CFD1200') as chnl
			WHERE chnl.Channel in (1,2,3);

		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load CFD1200' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @dtTimerDate  = SYSDATETIME();
		END

		IF EXISTS (SELECT 'X' FROM #RunMe WHERE AutoFraudTypeCode = 'PFD1000')
			INSERT INTO #AL(KeyId, OrgId, AutoFraudTypeId)
			SELECT DISTINCT PayerId, ClientOrgId, AutoFraudTypeId
			FROM (SELECT i.PayerId, [common].[ufnOrgClientId](p.OrgId) as ClientOrgId,  [common].[ufnOrgChannelId](p.OrgId) as Channel, rm.AutoFraudTypeId,
						ISNULL(ajs.PayerClearedItemCount,0) AS PayerClearedItemCount
					FROM  [ifa].[Item] i WITH (READUNCOMMITTED)
					INNER JOIN [ifa].[Process] p WITH (READUNCOMMITTED) on i.ProcessId = p.ProcessId
					INNER JOIN [payer].[Payer] pa WITH (READUNCOMMITTED) on i.PayerId = pa.PayerId
					CROSS APPLY #RunMe rm 
					OUTER APPLY [stat].[ufnAutoJobStat](i.PayerId,p.CustomerId) ajs
					WHERE i.DateActivated BETWEEN rm.StartDate AND rm.EndDate
						AND i.CheckAmount > 300
						AND ISNULL(TRY_CONVERT(BIGINT,i.CheckNumber),0) BETWEEN 3 AND 1000
						AND [common].[ufnOnUs]([common].[ufnOrgClientId](p.OrgId),pa.RoutingNumber,pa.AccountNumber) = 0
						AND rm.AutoFraudTypeCode = 'PFD1000') as chnl
			WHERE chnl.Channel in (1,2,3)
				AND chnl.PayerClearedItemCount = 0;

		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load PFD1000' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @dtTimerDate  = SYSDATETIME();
		END

		IF EXISTS (SELECT 'X' FROM #RunMe WHERE AutoFraudTypeCode = 'CCFD1000')
			INSERT INTO #AL(KeyId, OrgId, AutoFraudTypeId)
			SELECT DISTINCT CustomerId, ClientOrgId, AutoFraudTypeId
			FROM (SELECT DISTINCT p.CustomerId, [common].[ufnOrgClientId](p.OrgId) as ClientOrgId,  [common].[ufnOrgChannelId](p.OrgId) as Channel, rm.AutoFraudTypeId,
						ISNULL(ajs.PayerClearedItemCount,0) AS PayerClearedItemCount
					FROM  [ifa].[Item] i WITH (READUNCOMMITTED)
					INNER JOIN [ifa].[Process] p WITH (READUNCOMMITTED) on i.ProcessId = p.ProcessId
					INNER JOIN [payer].[Payer] pa WITH (READUNCOMMITTED) on i.PayerId = pa.PayerId
					CROSS APPLY #RunMe rm 
					OUTER APPLY [stat].[ufnAutoJobStat](i.PayerId,p.CustomerId) ajs
					WHERE i.DateActivated BETWEEN rm.StartDate AND rm.EndDate
						AND ISNULL(TRY_CONVERT(BIGINT,i.CheckNumber),0) BETWEEN 3 AND 99
						AND i.CheckAmount > 100
						AND [common].[ufnOnUs]([common].[ufnOrgClientId](p.OrgId),pa.RoutingNumber,pa.AccountNumber) = 0
						AND rm.AutoFraudTypeCode = 'CCFD1000') as chnl
			WHERE chnl.Channel in (1,2,3)
				AND chnl.PayerClearedItemCount = 0;

		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load CCFD1000' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @dtTimerDate  = SYSDATETIME();
		END

		IF EXISTS (SELECT 'X' FROM #RunMe WHERE AutoFraudTypeCode = 'CCFD2000')
			INSERT INTO #AL(KeyId, OrgId, AutoFraudTypeId)
			SELECT DISTINCT CustomerId, ClientOrgId, AutoFraudTypeId
			FROM (SELECT DISTINCT p.CustomerId, [common].[ufnOrgClientId](p.OrgId) as ClientOrgId,  [common].[ufnOrgChannelId](p.OrgId) as Channel, rm.AutoFraudTypeId,
					ISNULL(ajs.KCPClearedDepositCount,0) AS KCPClearedDepositCount
					FROM  [ifa].[Item] i WITH (READUNCOMMITTED)
					INNER JOIN [ifa].[Process] p WITH (READUNCOMMITTED) on i.ProcessId = p.ProcessId
					INNER JOIN [payer].[Payer] pa WITH (READUNCOMMITTED) on i.PayerId = pa.PayerId
					CROSS APPLY #RunMe rm 
					OUTER APPLY [stat].[ufnAutoJobStat](i.PayerId,p.CustomerId) ajs
					WHERE i.DateActivated BETWEEN rm.StartDate AND rm.EndDate
						AND i.CheckAmount = ROUND(i.CheckAmount,-2)
						AND i.CheckAmount > 200
						AND pa.RoutingNumber <> '000000518'
						AND ISNULL(TRY_CONVERT(BIGINT,i.CheckNumber),0) > 99999
						AND [common].[ufnOnUs]([common].[ufnOrgClientId](p.OrgId),pa.RoutingNumber,pa.AccountNumber) = 0
						AND rm.AutoFraudTypeCode = 'CCFD2000') as chnl
			WHERE chnl.Channel in (1,2,3)
				AND chnl.KCPClearedDepositCount = 0;

		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load CCFD2000' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @dtTimerDate  = SYSDATETIME();
		END

		IF EXISTS (SELECT 'X' FROM #RunMe WHERE AutoFraudTypeCode = 'CCFD3000')
			INSERT INTO #AL(KeyId, OrgId, AutoFraudTypeId)
			SELECT DISTINCT CustomerId, ClientOrgId, AutoFraudTypeId
			FROM (SELECT DISTINCT p.CustomerId, [common].[ufnOrgClientId](p.OrgId) as ClientOrgId,  [common].[ufnOrgChannelId](p.OrgId) as Channel, rm.AutoFraudTypeId,
					ISNULL(ajs.PayerClearedItemCount,0) AS PayerClearedItemCount,
					ISNULL(ajs.CustCurrentBalance,0) AS CurrentBalance
					FROM  [ifa].[Item] i WITH (READUNCOMMITTED)
					INNER JOIN [ifa].[Process] p WITH (READUNCOMMITTED) on i.ProcessId = p.ProcessId
					INNER JOIN [payer].[Payer] pa WITH (READUNCOMMITTED) on i.PayerId = pa.PayerId
					CROSS APPLY #RunMe rm 
					OUTER APPLY [stat].[ufnAutoJobStat](i.PayerId,p.CustomerId) ajs
					WHERE i.DateActivated BETWEEN rm.StartDate AND rm.EndDate
						AND i.CheckAmount > 100
						AND [common].[ufnOnUs]([common].[ufnOrgClientId](p.OrgId),pa.RoutingNumber,pa.AccountNumber) = 0
						AND rm.AutoFraudTypeCode = 'CCFD3000') as chnl
			WHERE chnl.Channel in (1,2,3)
				AND chnl.CurrentBalance < 50
				AND chnl.PayerClearedItemCount = 0;

		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load CCFD3000' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @dtTimerDate  = SYSDATETIME();
		END

		IF EXISTS (SELECT 'X' FROM #RunMe WHERE AutoFraudTypeCode = 'CCFD4000')
			INSERT INTO #AL(KeyId, OrgId, AutoFraudTypeId)
			SELECT DISTINCT CustomerId, ClientOrgId, AutoFraudTypeId
			FROM (SELECT DISTINCT p.CustomerId, [common].[ufnOrgClientId](p.OrgId) as ClientOrgId,  [common].[ufnOrgChannelId](p.OrgId) as Channel, rm.AutoFraudTypeId
					FROM  [ifa].[Item] i WITH (READUNCOMMITTED)
					INNER JOIN [ifa].[Process] p WITH (READUNCOMMITTED) on i.ProcessId = p.ProcessId
					INNER JOIN [riskprocessing].[RPResult] rpr WITH (READUNCOMMITTED) on i.ItemId = rpr.ItemId
																AND rpr.Msg = 'DuplicateItem(1)' 
					CROSS APPLY #RunMe rm 
					WHERE i.DateActivated BETWEEN rm.StartDate AND rm.EndDate
						AND i.CheckAmount > 20
						AND i.RuleBreak = 1
						AND i.RuleBreakResponse = 'Red|002'
						AND rm.AutoFraudTypeCode = 'CCFD4000') as chnl
			WHERE chnl.Channel in (3);	

		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load CCFD4000' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @dtTimerDate  = SYSDATETIME();
		END

		IF EXISTS (SELECT 'X' FROM #RunMe WHERE AutoFraudTypeCode = 'CCFD5000')
			INSERT INTO #AL(KeyId, OrgId, AutoFraudTypeId)
			SELECT DISTINCT CustomerId, ClientOrgId, AutoFraudTypeId
			FROM (SELECT DISTINCT p.CustomerId, [common].[ufnOrgClientId](p.OrgId) as ClientOrgId,  [common].[ufnOrgChannelId](p.OrgId) as Channel, rm.AutoFraudTypeId
					FROM  [ifa].[Item] i WITH (READUNCOMMITTED)
					INNER JOIN [ifa].[Process] p WITH (READUNCOMMITTED) on i.ProcessId = p.ProcessId
					CROSS APPLY #RunMe rm 
					WHERE i.DateActivated BETWEEN rm.StartDate AND rm.EndDate
						AND i.CheckAmount BETWEEN 25 AND 5000
						AND i.RuleBreak = 1
						AND rm.AutoFraudTypeCode = 'CCFD5000') as chnl
			WHERE chnl.Channel in (3);

		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load CCFD5000' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @dtTimerDate  = SYSDATETIME();
		END
							
		--UPDATE those that exist, but need a date refresh....
		UPDATE al0
			SET StatusFlag = 0
				,DateActivated = SYSDATETIME()
		OUTPUT deleted.AutoFraudId
			,deleted.AutoFraudTypeId
			,deleted.OrgId
			,deleted.KeyId
			,deleted.StatusFlag
			,deleted.DateActivated
			,deleted.DateExpired
			,deleted.UserName
		INTO #AutoFraud
		FROM [ifa].[AutoFraud] al0
		INNER JOIN #AL al ON al0.AutoFraudTypeId = al.AutoFraudTypeId
							AND al0.OrgId = al.OrgId 
							AND al0.KeyId = al.KeyId
		INNER JOIN #AutoFraudType alt ON al.AutoFraudTypeId = alt.AutoFraudTypeId
										AND al0.StatusFlag = 1
										AND al0.DateExpired > @dtNow
										AND al0.DateExpired < dateadd(day,alt.DateExpiredDays,@dtNow);

		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Update AutoFraud' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @dtTimerDate  = SYSDATETIME();
		END

		--INSERT those that don't exist
		INSERT INTO [ifa].[AutoFraud](AutoFraudTypeId,OrgId,KeyId,StatusFlag,DateActivated,DateExpired,UserName)
		SELECT alt.AutoFraudTypeId,al.OrgId,al.KeyId,1,sysdatetime(),dateadd(day,alt.DateExpiredDays,@dtNow),'AutoFraud'
		FROM #AL al
		INNER JOIN #AutoFraudType alt ON al.AutoFraudTypeId = alt.AutoFraudTypeId
		WHERE NOT EXISTS (SELECT 'X' FROM [ifa].[AutoFraud] al0 
							WHERE al.AutoFraudTypeId = al0.AutoFraudTypeId 
								AND al.OrgId = al0.OrgId 
								AND al.KeyId = al0.KeyId
								AND al0.StatusFlag = 1 --with this requiremnt we will 're-add' those that need a date extension
								AND al0.DateExpired > @dtNow);

		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Insert AutoFraud' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @dtTimerDate  = SYSDATETIME();
		END

		CLOSE SYMMETRIC KEY VALIdSymKey;
		--UPDATE job records
		UPDATE alj
			SET DateLastExecuted = @dtNow
				,DateActivated = sysdatetime()
		FROM [ifa].[AutoFraudJob] alj
		INNER JOIN #AutoFraudJob alj0 on alj.AutoFraudJobId = alj0.AutoFraudJobId
		WHERE EXISTS (SELECT 'X' FROM #RunMe WHERE alj0.AutoFraudJobId = AutoFraudJobId);

		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Update AutoFraudJob' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @dtTimerDate  = SYSDATETIME();
		END

	END

	--DEACTIVATE those that have expired...
	UPDATE al
		SET StatusFlag = 0
			,DateActivated = SYSDATETIME()
	FROM [ifa].[AutoFraud] al
	INNER JOIN #DAL dal on al.AutoFraudId = dal.AutoFraudId;

	IF @iLogLevel > 0
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit' ,DATEDIFF(microsecond,@dtInitial,SYSDATETIME()),SYSDATETIME());
		SET @dtTimerDate  = SYSDATETIME();
	END

drop table #AutoFraudType
drop table #AutoFraud
drop table #AutoFraudJob
drop table #RunMe
drop table #AL
drop table #DAL
END
