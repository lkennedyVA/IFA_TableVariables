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
		2022-07-26 - LBD - Recreating, to minimize data pulls
		2025-01-09 - LXK - Replaced table variables with local temp tables
*****************************************************************************************/
ALTER   PROCEDURE [ifa].[uspAutoFraudJobLarry](
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
		,@iRowCnt int
		,@dtS datetime2(7)
		,@dtE datetime2(7);

	--2022-07-26
	drop table if exists #AutoFraudJobLarry
	create table #AutoFraudJobLarry(ItemId bigint primary key
		,CheckAmount money
		,CustomerId bigint
		,OrgClientId int
		,OrgId int
		,Channel int
		,CheckNumberStr nvarchar(50)
		,CheckNumber bigint
		,PayerId bigint
		,OnUsFlag bit
		,RoutingNumber nchar(9)
		,AccountNumber nvarchar(50)
		,RuleBreak nvarchar(25)
		,RuleBreakResponse nvarchar(255)
		,DateActivated datetime2(7)
		,CustClearedItemCount int					--N'CFD1200'
		,PayerClearedItemCount int					--N'CFD1000','PFD1000',N'CCFD1000',N'CCFD3000'  ISNULL(ajs.PayerClearedItemCount,0)
		,CustOpenDateGreaterThan90 bit				--N'CFD1200' DATEDIFF(DAY,ajs.CustOpenDate,GETDATE()) > 90	
		,KCPClearedDepositCount int					--N'CCFD2000' ISNULL(ajs.KCPClearedDepositCount,0) 
		,CurrentBalance money						--N'CCFD3000' ISNULL(ajs.CustCurrentBalance,0)
	);

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

	IF @iLogLevel > 0
	BEGIN
		--INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		--VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Enter' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
		SELECT @ncProcessKey,@ncSchemaName,@ncObjectName,N'Enter' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()
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
		--INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		--VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Insert New Jobs' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
		SELECT @ncProcessKey,@ncSchemaName,@ncObjectName,N'Insert New Jobs' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME();
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
	--WHERE DATEADD(MINUTE,(FreqInHours*60.0)-1,alj.DateLastExecuted) <= @dtNow;

	IF @iLogLevel > 1
	BEGIN
		--INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		--VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load RunMe' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
		SELECT @ncProcessKey,@ncSchemaName,@ncObjectName,N'Load RunMe' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME();
		SET @dtTimerDate  = SYSDATETIME();
	END

	--ANY TO Deactivate?
	INSERT INTO #DAL(AutoFraudId)
	SELECT AutoFraudId
	FROM [ifa].[AutoFraud] 
	WHERE DateExpired <= @dtNow
		AND StatusFlag = 1;

	--2022-07-
	IF EXISTS (SELECT 'X' FROM #RunMe)
	BEGIN
		OPEN SYMMETRIC KEY VALIdSymKey DECRYPTION BY ASYMMETRIC KEY [VALIDASYMKEY]; 
		--PRELOAD BASED ON LONGEST TIME FRAME
		IF EXISTS (SELECT 'X' FROM #RunMe WHERE AutoFraudTypeCode in (N'CFD1100',N'CCFD2000'))
		BEGIN
			SET @dtS = getdate()-1;
			SET @dtE = dateadd(day,+1,@dtS);
			INSERT INTO #AutoFraudJobLarry(ItemId, CheckAmount, CheckNumberStr, CheckNumber, OrgId, CustomerId, PayerId, RoutingNumber, AccountNumber)
			SELECT i.ItemId, i.CheckAmount, i.CheckNumber as CheckNumberStr
				,ISNULL(TRY_CONVERT(BIGINT,i.CheckNumber),0) as CheckNumber, p.OrgId, p.CustomerId, i.PayerId, pa.RoutingNumber, pa.AccountNumber
			FROM  [ifa].[Item] i WITH (READUNCOMMITTED)
			INNER JOIN [ifa].[Process] p WITH (READUNCOMMITTED) on i.ProcessId = p.ProcessId
			INNER JOIN [payer].[Payer] pa WITH (READUNCOMMITTED) on i.PayerId = pa.PayerId
			WHERE i.DateActivated BETWEEN @dtS AND @dtE;
		END
		ELSE
		BEGIN
			SET @dtS = dateadd(hour,-1,getdate());
			SET @dtE = dateadd(hour,1,@dtS);
			INSERT INTO #AutoFraudJobLarry(ItemId, CheckAmount, CheckNumberStr, CheckNumber, OrgId, CustomerId, PayerId, RoutingNumber, AccountNumber)
			SELECT i.ItemId, i.CheckAmount, i.CheckNumber as CheckNumberStr 
				,ISNULL(TRY_CONVERT(BIGINT,i.CheckNumber),0) as CheckNumber, p.OrgId, p.CustomerId, i.PayerId, pa.RoutingNumber, pa.AccountNumber
			FROM  [ifa].[Item] i WITH (READUNCOMMITTED)
			INNER JOIN [ifa].[Process] p WITH (READUNCOMMITTED) on i.ProcessId = p.ProcessId
			INNER JOIN [payer].[Payer] pa WITH (READUNCOMMITTED) on i.PayerId = pa.PayerId
			WHERE i.DateActivated BETWEEN @dtS AND @dtE;
		END

		SELECT @@ROWCOUNT as GatheringItemsCount

		IF @iLogLevel > 1
		BEGIN
			--INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			--VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Gathering Items' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SELECT @ncProcessKey,@ncSchemaName,@ncObjectName,N'Gathering Items' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME();
			SET @dtTimerDate  = SYSDATETIME();
		END

		--Gather Client, Channel, AutoJobStats
		UPDATE d
			SET OrgClientId = [common].[ufnOrgClientId](d.OrgId)
				,Channel = [common].[ufnOrgChannelId](d.OrgId)
				,PayerClearedItemCount = ISNULL(ajs.PayerClearedItemCount,0)
				,KCPClearedDepositCount = ISNULL(ajs.KCPClearedDepositCount,0)
				,CurrentBalance = ISNULL(ajs.CustCurrentBalance,0)
				,CustOpenDateGreaterThan90 = CASE WHEN DATEDIFF(DAY,ajs.CustOpenDate,GETDATE()) > 90 THEN 1 ELSE 0 END
		FROM #AutoFraudJobLarry d
		OUTER APPLY [stat].[ufnAutoJobStat](d.PayerId,d.CustomerId) ajs;

		IF @iLogLevel > 1
		BEGIN
			--INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			--VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Gathering Item Details' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SELECT @ncProcessKey,@ncSchemaName,@ncObjectName,N'Gathering Item Details' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()
			SET @dtTimerDate  = SYSDATETIME();
		END
		
		IF EXISTS (SELECT 'X' FROM #RunMe WHERE AutoFraudTypeCode in (N'CFD1000',N'CFD1200','PFD1000',N'CCFD1000',N'CCFD2000',N'CCFD3000'))
			--OnUsFlag
			UPDATE d
				SET OnUsFlag = [common].[ufnOnUs](d.OrgClientId,d.RoutingNumber,d.AccountNumber)
			FROM #AutoFraudJobLarry d;

		IF @iLogLevel > 1
		BEGIN
			--INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			--VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Gathering OnUsFlag' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SELECT @ncProcessKey,@ncSchemaName,@ncObjectName,N'Gathering OnUsFlag' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()
			SET @dtTimerDate  = SYSDATETIME();
		END

/*		
		--GENERATE any that are timely
		IF EXISTS (SELECT 'X' FROM #RunMe WHERE AutoFraudTypeCode = N'CFD1000')
			INSERT INTO #AL(KeyId, OrgId, AutoFraudTypeId)
			SELECT DISTINCT CustomerId, OrgClientId, AutoFraudTypeId
			FROM (SELECT d.CustomerId, d.OrgClientId, rm.AutoFraudTypeId
				FROM #AutoFraudJobLarry d
				CROSS APPLY #RunMe rm 
				WHERE d.DateActivated BETWEEN rm.StartDate AND rm.EndDate
					AND d.CheckNumber BETWEEN 1 AND 350
					AND d.CheckAmount > 500.00 
					AND d.OnUsFlag = 0
					AND rm.AutoFraudTypeCode = N'CFD1000'
					AND d.PayerClearedItemCount = 0
					AND d.Channel in (1,2,3)
			) AS drm;

		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load CFD1000' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @dtTimerDate  = SYSDATETIME();
		END

		IF EXISTS (SELECT 'X' FROM #RunMe WHERE AutoFraudTypeCode = N'CFD1100')
			INSERT INTO #AL(KeyId, OrgId, AutoFraudTypeId)
			SELECT DISTINCT CustomerId, OrgClientId, AutoFraudTypeId
			FROM (SELECT d.CustomerId, d.OrgClientId, rm.AutoFraudTypeId
				FROM #AutoFraudJobLarry d
				CROSS APPLY #RunMe rm 
				WHERE d.DateActivated BETWEEN rm.StartDate AND rm.EndDate
					AND d.RoutingNumber = N'000000518'
					AND (
							(LEN(d.CheckNumberStr) = 8
								AND (ISNULL(TRY_CONVERT(BIGINT,d.CheckNumberStr),0)%11) not in (0,10)
							)
						or
							(LEN(d.CheckNumberStr) = 9
								AND ((ISNULL(TRY_CONVERT(BIGINT,d.CheckNumberStr),0)%10) - (ISNULL(TRY_CONVERT(INT,SUBSTRING(d.CheckNumberStr,1,8)),0) %11)
									) <> 0
							)
						)
					AND rm.AutoFraudTypeCode = N'CFD1100') AS drm;

		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load CFD1100' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @dtTimerDate  = SYSDATETIME();
		END

		IF EXISTS (SELECT 'X' FROM #RunMe WHERE AutoFraudTypeCode = N'CFD1200')
			INSERT INTO #AL(KeyId, OrgId, AutoFraudTypeId)
			SELECT DISTINCT CustomerId, OrgClientId, AutoFraudTypeId
			FROM (SELECT d.CustomerId, d.OrgClientId, rm.AutoFraudTypeId
					FROM #AutoFraudJobLarry d
					CROSS APPLY #RunMe rm 
					WHERE d.DateActivated BETWEEN rm.StartDate AND rm.EndDate
						AND d.CustClearedItemCount = 0
						AND d.CustOpenDateGreaterThan90 = 1
						AND d.CheckAmount > 100.00
						AND d.OnUsFlag = 0
						AND rm.AutoFraudTypeCode = N'CFD1200'
						AND d.Channel in (1,2,3)) as drm;

		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load CFD1200' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @dtTimerDate  = SYSDATETIME();
		END

		IF EXISTS (SELECT 'X' FROM #RunMe WHERE AutoFraudTypeCode = N'PFD1000')
			INSERT INTO #AL(KeyId, OrgId, AutoFraudTypeId)
			SELECT DISTINCT PayerId, OrgClientId, AutoFraudTypeId
			FROM (SELECT d.PayerId,d.OrgClientId, rm.AutoFraudTypeId
					FROM #AutoFraudJobLarry d
					CROSS APPLY #RunMe rm 
					WHERE d.DateActivated BETWEEN rm.StartDate AND rm.EndDate
						AND d.CheckAmount > 300.00
						AND d.CheckNumber BETWEEN 3 AND 1000
						AND d.OnUsFlag = 0
						AND rm.AutoFraudTypeCode = N'PFD1000'
						AND d.Channel in (1,2,3)
						AND d.PayerClearedItemCount = 0) AS drm;

		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load PFD1000' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @dtTimerDate  = SYSDATETIME();
		END

		IF EXISTS (SELECT 'X' FROM #RunMe WHERE AutoFraudTypeCode = N'CCFD1000')
			INSERT INTO #AL(KeyId, OrgId, AutoFraudTypeId)
			SELECT DISTINCT CustomerId, OrgClientId, AutoFraudTypeId
			FROM (SELECT d.CustomerId, d.OrgClientId, rm.AutoFraudTypeId
					FROM #AutoFraudJobLarry d
					CROSS APPLY #RunMe rm 
					WHERE d.DateActivated BETWEEN rm.StartDate AND rm.EndDate
						AND d.CheckNumber BETWEEN 3 AND 99
						AND d.CheckAmount > 100.00
						AND d.OnUsFlag = 0
						AND rm.AutoFraudTypeCode = N'CCFD1000'
						AND d.Channel in (1,2,3)
						AND d.PayerClearedItemCount = 0) AS drm;

		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load CCFD1000' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @dtTimerDate  = SYSDATETIME();
		END

		IF EXISTS (SELECT 'X' FROM #RunMe WHERE AutoFraudTypeCode = N'CCFD2000')
			INSERT INTO #AL(KeyId, OrgId, AutoFraudTypeId)
			SELECT DISTINCT CustomerId, OrgClientId, AutoFraudTypeId
			FROM (SELECT d.CustomerId, d.OrgClientId,  rm.AutoFraudTypeId
					FROM #AutoFraudJobLarry d
					CROSS APPLY #RunMe rm
					WHERE d.DateActivated BETWEEN rm.StartDate AND rm.EndDate
						AND d.CheckAmount = ROUND(d.CheckAmount,-2)
						AND d.CheckAmount > 200.00
						AND d.RoutingNumber <> N'000000518'
						AND d.CheckNumber > 99999
						AND d.OnUsFlag = 0
						AND rm.AutoFraudTypeCode = N'CCFD2000'
						AND d.Channel in (1,2,3)
						AND d.KCPClearedDepositCount = 0) AS drm;

		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load CCFD2000' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @dtTimerDate  = SYSDATETIME();
		END

		IF EXISTS (SELECT 'X' FROM #RunMe WHERE AutoFraudTypeCode = N'CCFD3000')
			INSERT INTO #AL(KeyId, OrgId, AutoFraudTypeId)
			SELECT DISTINCT CustomerId, OrgClientId, AutoFraudTypeId
			FROM (SELECT d.CustomerId, d.OrgClientId, rm.AutoFraudTypeId
					FROM #AutoFraudJobLarry d
					CROSS APPLY #RunMe rm
					WHERE d.DateActivated BETWEEN rm.StartDate AND rm.EndDate
						AND d.CheckAmount > 100.00
						AND d.OnUsFlag = 0
						AND rm.AutoFraudTypeCode = N'CCFD3000'
						AND d.Channel in (1,2,3)
						AND d.CurrentBalance < 50.00
						AND d.PayerClearedItemCount = 0) AS drm;

		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load CCFD3000' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @dtTimerDate  = SYSDATETIME();
		END

		IF EXISTS (SELECT 'X' FROM #RunMe WHERE AutoFraudTypeCode = N'CCFD4000')
			INSERT INTO #AL(KeyId, OrgId, AutoFraudTypeId)
			SELECT DISTINCT CustomerId, OrgClientId, AutoFraudTypeId
			FROM (SELECT d.CustomerId, d.OrgClientId, rm.AutoFraudTypeId
					FROM #AutoFraudJobLarry d
					INNER JOIN [riskprocessing].[RPResult] rpr WITH (READUNCOMMITTED) on d.ItemId = rpr.ItemId
																AND rpr.Msg = 'DuplicateItem(1)' 
					CROSS APPLY #RunMe rm 
					WHERE d.DateActivated BETWEEN rm.StartDate AND rm.EndDate
						AND d.CheckAmount > 20.00
						AND d.RuleBreak = N'1'
						AND d.RuleBreakResponse = N'Red|002'
						AND rm.AutoFraudTypeCode = N'CCFD4000'
						AND d.Channel = 3) AS drm;	

		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Load CCFD4000' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @dtTimerDate  = SYSDATETIME();
		END

		IF EXISTS (SELECT 'X' FROM #RunMe WHERE AutoFraudTypeCode = N'CCFD5000')
			INSERT INTO #AL(KeyId, OrgId, AutoFraudTypeId)
			SELECT DISTINCT CustomerId, OrgClientId, AutoFraudTypeId
			FROM (SELECT d.CustomerId, d.OrgClientId, rm.AutoFraudTypeId
					FROM #AutoFraudJobLarry d
					CROSS APPLY #RunMe rm
					WHERE d.DateActivated BETWEEN rm.StartDate AND rm.EndDate
						AND d.CheckAmount BETWEEN 25.00 AND 5000.00
						AND d.RuleBreak = N'1'
						AND rm.AutoFraudTypeCode = N'CCFD5000'
						AND d.Channel = 3) AS drm;

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
	*/
	END
	IF @iLogLevel > 0
	BEGIN
		--INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		--VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit' ,DATEDIFF(microsecond,@dtInitial,SYSDATETIME()),SYSDATETIME());
		SELECT @ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit' ,DATEDIFF(microsecond,@dtInitial,SYSDATETIME()),SYSDATETIME()
	END
END
