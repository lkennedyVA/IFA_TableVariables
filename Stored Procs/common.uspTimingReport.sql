USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspTimingReport
	CreatedBy: Larry Dugger
	Descr: This procedure will SELECT record(s)

	Tables: [dbo].[IFATiming]
		,[ifa].[Item]
		,[ifa].[Process]
		,[mac].[DuplicateItem]
		,[stat].[NewDuplicateItem]
		,[ValidBankLogging].[dbo].[TransactionLogCalc]
		,[ValidBankLogging].[dbo].[TransactionPluginLogCalc]
   
	History:
		2015-05-07 - LBD - Created
		2018-05-09 - LBD - Modified, took out direct link to Condensed.
		2019-03-10 - LBD - Modified, cleaned-up, and organized some.
		2019-05-01 - LBD - Modified, uses new [mac].[DuplicateItem] table
		2019-06-12 - LBD - Modified, added Rtla to #tblVaePluginRpt
		2025-01-08 - LXK - Removed table variables for better performance
*****************************************************************************************/
ALTER PROCEDURE [common].[uspTimingReport](
	 @piBitMask INT = 1
	,@piMsThreshold INT = 500
	,@pdtMinutes INT = -10
	,@piTransToSee INT = 20
	,@pdtTimeOuts DATETIME = NULL
	,@pdtTimeOuts2 DATETIME = NULL
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #tblTCLRpt
	create table #tblTCLRpt(
		[Name] nvarchar(50)
		,Id bigint primary key
		,LogId bigint
		,[Status] nchar(4) 
		,ProcessId bigint
		,TransactionKey nchar(25) 
		,DateSubmitted [datetime2](7) 
		,RequestInMs int 
		,ConfirmInMs int 
		,OrgName nvarchar(50)
		,OrgId int
		,DateActivated datetime2(7) 
	);
	drop table if exists #tblTodayLoadStatsRpt
	create table #tblTodayLoadStatsRpt(
		[Name] nvarchar(50)
		,IFATimingId int primary key
		,ProcessKey nchar(25)
		,SchemaName nchar(20)
		,ObjectName nchar(50)
		,Msg nchar(50)
		,Microseconds bigint
		,DateExecuted datetime2(7)
		,DateActivated datetime2(7)
	);
	drop table if exists #tblNewDupItemRpt
	create table #tblNewDupItemRpt(
		[Name] nvarchar(50)
		,NewDupItemCnt int
	);
	drop table if exists #tblDupItemRpt
	create table #tblDupItemRpt(
		[Name] nvarchar(50)
		,DupItemCnt int
	);	
	drop table if exists #tblRcntItemRpt
	create table #tblRcntItemRpt(
		[Name] nvarchar(50)
		,OrgId int
		,ProcessId bigint
		,ItemId bigint
		,checkamount money
		,amount money 
		,fee money
		,ItemStatusId int
		,ClientAcceptedId int
		,RuleBreak nvarchar(25)
		,RuleBreakResponse nvarchar(255)
		,UserName nvarchar(100)
		,DateActivated datetime2(7)
		,primary key (ProcessId desc, ItemId desc)
	);	
	drop table if exists #tblTimingRpt
	create table #tblTimingRpt(
		[Name] nvarchar(50)
		,Trans int
		,[AvgMs] int
		,[>1s] int
		,[>2s] int
		,[>3s] int
		,[>5s] int
		,[>10s] int
		,[Day-Hour] nvarchar(13)  primary key
	);
	drop table if exists #tblIFATiming
	create table #tblIFATiming(
		[Name] nvarchar(50)
		,IFATimingId int primary key
		,ProcessKey nchar(25)
		,SchemaName nchar(20)
		,ObjectName nchar(50)
		,Msg nchar(50)
		,Microseconds bigint
		,DateExecuted datetime2(7)
		,DateActivated datetime2(7)
	);
	drop table if exists #tblTransactionLogCalc
	create table #tblTransactionLogCalc(
		[Name] nvarchar(50)
		,Id bigint primary key
		,LogId bigint
		,[Status] nchar(4) 
		,ProcessId bigint
		,TransactionKey nchar(25) 
		,DateSubmitted [datetime2](7) 
		,RequestInMs int 
		,ConfirmInMs int 
		,OrgName nvarchar(50)
		,OrgId int
		,DateActivated datetime2(7) 
	);
	drop table if exists #tblTranRpt
	create table #tblTranRpt(
		[Name] nvarchar(50)
		,Cnt int
		,MinReq int
		,AvgReq int
		,MaxReq int
		,MinCon int
		,AvgCon int
		,MaxCon int
		,Dt nvarchar(16)
		,Span nchar(10) primary key
	);
	drop table if exists #tblTimeOutsRpt
	create table #tblTimeOutsRpt(
		[Name] nvarchar(50)
		,Trans int
		,[>1s] int
		,[>2s] int
		,[>3s] int
		,[>5s] int
		,[>10s] int
		,[Day-Hour] nvarchar(13) primary key
	);
	drop table if exists #tblVaePluginRpt
	create table #tblVaePluginRpt(
		[Name] nvarchar(50)
		,Trans int
		,MinVae int
		,AvgVae int
		,MaxVae int
		,StdedpVae int
		,MinFraud int
		,AvgFraud int
		,MaxFraud int
		,StdedpFraud int
		,MinRtla int
		,AvgRtla int
		,MaxRtla int
		,StdedpRtla int
	);
	drop table if exists #tblActualDBTimeRpt
	create table #tblActualDBTimeRpt(
		[Name] nvarchar(50)
		,DBRequestInMs int
		,RequestInMs int
		,ConfirmInMS int
		,IFATimingId int
		,ProcessKey nchar(25)
		,SchemaName nchar(20)
		,ObjectName nchar(50)
		,Msg nchar(50)
		,Microseconds bigint
		,DateExecuted datetime2(7)
		,DateActivated datetime2(7)
	);
	drop table if exists #tblItem
	create table #tblItem(
		ItemId bigint primary key
		,TransactionKey nchar(25)
	);
	drop table if exists #tblItemTimingRpt
	create table #tblItemTimingRpt(
		[Name] nvarchar(50)
		,TimeMs int
		,ItemId bigint
		,TransactionKey nchar(25)
	);
	drop table if exists #tbl5MinuteActivity
	create table #tbl5MinuteActivity(
		[Name] nvarchar(50)
		,Cnt int
		,[Hour] nchar(2)
		,[Minute] nchar(2)
		,Mobile bit
	);

	DECLARE @iBitMask int = @piBitMask
		,@iMsThreshold int = @piMsThreshold
		,@iTransToSee int = @piTransToSee
		,@dtTimeOuts datetime = ISNULL(@pdtTimeOuts,getdate()-1)
		,@dtTimeOuts2 datetime = ISNULL(@pdtTimeOuts2,getdate())
		,@dt datetime2(7) = dateadd(minute,@pdtMinutes,getdate())
		,@dt5min datetime2(7) =	dateadd(minute,-5,sysdatetime());

	IF @iBitMask & 1 != 0
	BEGIN
		INSERT INTO #tblTCLRpt([Name],Id,LogId,[Status],ProcessId,TransactionKey,DateSubmitted,RequestInMs,ConfirmInMs,OrgName,OrgId,DateActivated)
		SELECT 'TCLRpt',Id,LogId,[Status],ProcessId,TransactionKey,DateSubmitted,RequestInMs,ConfirmInMs,OrgName,OrgId,DateActivated
		FROM [ValidBankLogging].[dbo].[TransactionLogCalc] WITH (READUNCOMMITTED) 
		WHERE [DateSubmitted] > @dt
			AND (RequestInMs > @iMsThreshold or ConfirmInMs > @iMsThreshold)
		ORDER BY Id DESC;
		IF EXISTS (SELECT 'X' FROM #tblTCLRpt)
			SELECT [Name],Id,LogId,[Status],ProcessId,TransactionKey,DateSubmitted,RequestInMs,ConfirmInMs,OrgName,OrgId,DateActivated
			FROM #tblTCLRpt
			ORDER BY Id DESC;
	END
	IF @iBitMask & 2 != 0
	BEGIN
		INSERT INTO #tblTodayLoadStatsRpt([Name],IFATimingId, ProcessKey, SchemaName,ObjectName, Msg, Microseconds, DateExecuted, DateActivated)
		SELECT TOP 100 'TodayLoadStatsRpt',IFATimingId, ProcessKey, SchemaName,ObjectName, Msg, Microseconds, DateExecuted, DateActivated
		FROM [dbo].[IFATiming] WITH (READUNCOMMITTED) 
		WHERE ObjectName = 'uspLoadStats' 
			AND DateActivated > CONVERT(DATE,GETDATE())
		ORDER BY IFATimingId;
		IF EXISTS (SELECT 'X' FROM #tblTodayLoadStatsRpt)
			SELECT [Name],IFATimingId, ProcessKey, SchemaName,ObjectName, Msg, Microseconds, DateExecuted, DateActivated
			FROM #tblTodayLoadStatsRpt
			ORDER BY IFATimingId;
	END
	IF @iBitMask & 4 != 0
	BEGIN
		INSERT INTO #tblNewDupItemRpt([Name],NewDupItemCnt)
		SELECT 'NewDupItemRpt',COUNT(1) 
		FROM [stat].[NewDuplicateItem] WITH (READUNCOMMITTED);
		IF EXISTS (SELECT 'X' FROM #tblNewDupItemRpt)
			SELECT [Name],NewDupItemCnt
			FROM #tblNewDupItemRpt;
	END
	IF @iBitMask & 8 != 0
	BEGIN
		INSERT INTO #tblDupItemRpt([Name],DupItemCnt)
		SELECT 'DupItemRpt',COUNT(1)
		FROM [mac].[DuplicateItem] WITH (READUNCOMMITTED);
		IF EXISTS (SELECT 'X' FROM #tblDupItemRpt)
		SELECT [Name],DupItemCnt
		FROM #tblDupItemRpt;
	END
	IF @iBitMask & 16 != 0	 
	BEGIN
		INSERT INTO #tblRcntItemRpt([Name],OrgId,ProcessId,ItemId,checkamount,amount,fee
			,ItemStatusId,ClientAcceptedId,RuleBreak,RuleBreakResponse,UserName,DateActivated )
		SELECT TOP (@iTransToSee)'RcntItemRpt',p.OrgId,i.ProcessId,i.ItemId,i.checkamount,i.amount,i.fee
			,i.ItemStatusId,i.ClientAcceptedId, i.RuleBreak,i.RuleBreakResponse,i.UserName, i.DateActivated 
		FROM [ifa].[Item] i WITH (READUNCOMMITTED) 
		INNER JOIN [ifa].[Process] p WITH (READUNCOMMITTED) ON i.ProcessId = p.ProcessId
		ORDER BY p.ProcessId DESC, ItemId DESC
		IF EXISTS (SELECT 'X' FROM #tblRcntItemRpt)
			SELECT [Name],OrgId,ProcessId,ItemId,checkamount,amount,fee
				,ItemStatusId,ClientAcceptedId,RuleBreak,RuleBreakResponse,UserName,DateActivated
			FROM #tblRcntItemRpt
			ORDER BY Processid DESC, ItemId DESC;
	END
	IF @iBitMask & 32 != 0
	BEGIN
		INSERT INTO #tblTimingRpt([Name],Trans,[AvgMs],[>1s],[>2s],[>3s],[>5s],[>10s],[Day-Hour])
		SELECT 'TimingRpt',Trans,[AvgMs],[>1s],[>2s],[>3s],[>5s],[>10s],a1.dt
		FROM (SELECT count(*) Trans,convert(nvarchar(13),DateActivated,121) dt
			FROM [ifa].[Item] WITH (READUNCOMMITTED)
			WHERE @iBitMask & 32 != 0
				AND [DateActivated] between @dtTimeOuts and @dtTimeOuts2
			GROUP BY convert(nvarchar(13),DateActivated,121)) a1 
		LEFT OUTER JOIN (SELECT Avg(RequestInMs) 'Avgms',convert(nvarchar(13),DateSubmitted,121) dt
						FROM [ValidBankLogging].[dbo].[TransactionLogCalc] WITH (READUNCOMMITTED)
						WHERE [DateSubmitted] between @dtTimeOuts and @dtTimeOuts2
						GROUP BY convert(nvarchar(13),DateSubmitted,121)) a0 on a1.dt = a0.dt
		LEFT OUTER JOIN (SELECT count(*) '>1s',convert(nvarchar(13),DateSubmitted,121) dt
						FROM [ValidBankLogging].[dbo].[TransactionLogCalc] WITH (READUNCOMMITTED)
						WHERE [DateSubmitted] between @dtTimeOuts and @dtTimeOuts2
							AND (RequestInMs > 1000 or ConfirmInMs > 1000)
						GROUP BY convert(nvarchar(13),DateSubmitted,121)) a2 on a1.dt = a2.dt
		LEFT OUTER JOIN (SELECT count(*) '>2s',convert(nvarchar(13),DateSubmitted,121) dt
						FROM [ValidBankLogging].[dbo].[TransactionLogCalc] WITH (READUNCOMMITTED)
						WHERE [DateSubmitted] between @dtTimeOuts and @dtTimeOuts2
							AND (RequestInMs > 2000 or ConfirmInMs > 2000)
						GROUP BY convert(nvarchar(13),DateSubmitted,121)) a3 on a1.dt = a3.dt
		LEFT OUTER JOIN (SELECT count(*) '>3s',convert(nvarchar(13),DateSubmitted,121) dt
						FROM [ValidBankLogging].[dbo].[TransactionLogCalc] WITH (READUNCOMMITTED)
						WHERE [DateSubmitted] between @dtTimeOuts and @dtTimeOuts2
							AND (RequestInMs > 3000 or ConfirmInMs > 3000)
						GROUP BY convert(nvarchar(13),DateSubmitted,121)) a4 on a1.dt = a4.dt
		LEFT OUTER JOIN (SELECT count(*) '>5s',convert(nvarchar(13),DateSubmitted,121) dt
						FROM [ValidBankLogging].[dbo].[TransactionLogCalc] WITH (READUNCOMMITTED)
						WHERE [DateSubmitted] between @dtTimeOuts and @dtTimeOuts2
							AND (RequestInMs > 5000 or ConfirmInMs > 5000)
						GROUP BY convert(nvarchar(13),DateSubmitted,121)) a5 on a1.dt = a5.dt
		LEFT OUTER JOIN (SELECT count(*) '>10s',convert(nvarchar(13),DateSubmitted,121) dt
						FROM [ValidBankLogging].[dbo].[TransactionLogCalc] WITH (READUNCOMMITTED)
						WHERE [DateSubmitted] between @dtTimeOuts and @dtTimeOuts2
							AND (RequestInMs > 10000 or ConfirmInMs > 10000)
						GROUP BY convert(nvarchar(13),DateSubmitted,121)) a6 on a1.dt = a6.dt;
		IF EXISTS (SELECT 'X' FROM #tblTimingRpt)
			SELECT [Name],Trans,[AvgMs],[>1s],[>2s],[>3s],[>5s],[>10s],[Day-Hour]
			FROM #tblTimingRpt
			ORDER BY [Day-Hour] DESC;
	END
	IF @iBitMask & 64 != 0 
	BEGIN
		INSERT INTO #tblIFATiming([Name],IFATimingId, ProcessKey, SchemaName
			,ObjectName, Msg, Microseconds, DateExecuted, DateActivated)
		SELECT TOP 100 'IFATiming',IFATimingId, ProcessKey, SchemaName
			,ObjectName, Msg, Microseconds, DateExecuted, DateActivated
		FROM [dbo].[IFATiming] WITH (READUNCOMMITTED)
		ORDER BY IFATimingId desc;
		IF EXISTS (SELECT 'X' FROM #tblIFATiming)
			SELECT [Name],IFATimingId, ProcessKey, SchemaName
				,ObjectName, Msg, Microseconds, DateExecuted, DateActivated
			FROM #tblIFATiming
			ORDER BY IFATimingId DESC;
	END
	IF @iBitMask & 128 != 0
	BEGIN
		INSERT INTO #tblTransactionLogCalc([Name],Id,LogId,[Status],ProcessId,TransactionKey,DateSubmitted
			,RequestInMs,ConfirmInMs,OrgName,OrgId,DateActivated)
		SELECT 'TransactionLogCalc',Id,LogId,[Status],ProcessId,TransactionKey,DateSubmitted
			,RequestInMs,ConfirmInMs,OrgName,OrgId,DateActivated
		FROM [ValidBankLogging].[dbo].[TransactionLogCalc] WITH (READUNCOMMITTED) 
		WHERE  [DateSubmitted] > @dtTimeOuts
			AND (RequestInMs > 3000 or ConfirmInMs > 3000)
		ORDER BY LogId desc
		IF EXISTS (SELECT 'X' FROM #tblTransactionLogCalc)
			SELECT [Name],Id,LogId,[Status],ProcessId,TransactionKey,DateSubmitted
				,RequestInMs,ConfirmInMs,OrgName,OrgId,DateActivated
			FROM #tblTransactionLogCalc
			ORDER BY LogId DESC;
	END
	IF @iBitMask & 256 != 0
	BEGIN
		INSERT INTO #tblTranRpt([Name],Cnt,MinReq,AvgReq,MaxReq,MinCon,AvgCon,MaxCon,Dt,Span)
		SELECT 'TranRpt',count(1),min(tlc.RequestInMs),avg(tlc.RequestInMs),max(tlc.RequestInMs)
			,min(tlc.ConfirmInMs),avg(tlc.ConfirmInMs),max(tlc.ConfirmInMs)
			,convert(nvarchar(16),DateSubmitted,121),'DayHourMin'
		FROM [ValidBankLogging].[dbo].[TransactionLogCalc] tlc WITH (READUNCOMMITTED) 
		WHERE [DateSubmitted] BETWEEN @dtTimeOuts AND @dtTimeOuts2
		GROUP BY convert(nvarchar(16),DateSubmitted,121)
		ORDER BY 10 DESC
		IF EXISTS (SELECT 'X' FROM #tblTranRpt)
			SELECT [Name],Cnt,MinReq,AvgReq,MaxReq,MinCon,AvgCon,MaxCon,Dt,Span
			FROM #tblTranRpt
			ORDER BY Span DESC;
	END
	IF @iBitMask & 512 != 0
	BEGIN
		INSERT #tblTimeOutsRpt ([Name],Trans,[>1s],[>2s],[>3s],[>5s],[>10s],[Day-Hour])
		SELECT 'TimeOutsRpt',Trans,gt1s,gt2s,gt3s,gt5s,gt10s,a1.dt
		FROM (SELECT count(*) Trans,convert(nvarchar(13),DateActivated,121) dt
			FROM [ifa].[Item] 
			WHERE [DateActivated] between @dtTimeOuts and @dtTimeOuts2
			GROUP BY convert(nvarchar(13),DateActivated,121)) a1 
		LEFT OUTER JOIN (SELECT count(*) gt1s,convert(nvarchar(13),DateSubmitted,121) dt
						FROM [ValidBankLogging].[dbo].[TransactionLogCalc]  WITH (READUNCOMMITTED)  
						WHERE [DateSubmitted] between @dtTimeOuts and @dtTimeOuts2
							AND (RequestInMs > 1000 or ConfirmInMs > 1000)
						GROUP BY convert(nvarchar(13),DateSubmitted,121)) a2 on a1.dt = a2.dt
		LEFT OUTER JOIN (SELECT count(*) gt2s,convert(nvarchar(13),DateSubmitted,121) dt
						FROM [ValidBankLogging].[dbo].[TransactionLogCalc]  WITH (READUNCOMMITTED)  
						WHERE [DateSubmitted] between @dtTimeOuts and @dtTimeOuts2
							AND (RequestInMs > 2000 or ConfirmInMs > 2000)
						GROUP BY convert(nvarchar(13),DateSubmitted,121)) a3 on a1.dt = a3.dt
		LEFT OUTER JOIN (SELECT count(*) gt3s,convert(nvarchar(13),DateSubmitted,121) dt
						FROM [ValidBankLogging].[dbo].[TransactionLogCalc]  WITH (READUNCOMMITTED)  
						WHERE [DateSubmitted] between @dtTimeOuts and @dtTimeOuts2
							AND (RequestInMs > 3000 or ConfirmInMs > 3000)
						GROUP BY convert(nvarchar(13),DateSubmitted,121)) a4 on a1.dt = a4.dt
		LEFT OUTER JOIN (SELECT count(*) gt5s,convert(nvarchar(13),DateSubmitted,121) dt
						FROM [ValidBankLogging].[dbo].[TransactionLogCalc]  WITH (READUNCOMMITTED)  
						WHERE [DateSubmitted] between @dtTimeOuts and @dtTimeOuts2
							AND (RequestInMs > 5000 or ConfirmInMs > 5000)
						GROUP BY convert(nvarchar(13),DateSubmitted,121)) a5 on a1.dt = a5.dt
		LEFT OUTER JOIN (SELECT count(*) gt10s,convert(nvarchar(13),DateSubmitted,121) dt
						FROM [ValidBankLogging].[dbo].[TransactionLogCalc]  WITH (READUNCOMMITTED)  
						WHERE [DateSubmitted] between @dtTimeOuts and @dtTimeOuts2
							AND (RequestInMs > 10000 or ConfirmInMs > 10000)
						GROUP BY convert(nvarchar(13),DateSubmitted,121)) a6 on a1.dt = a6.dt
		ORDER BY 8 DESC
		IF EXISTS (SELECT 'X' FROM #tblTimeOutsRpt)
			SELECT [Name],Trans,[>1s],[>2s],[>3s],[>5s],[>10s],[Day-Hour]
			FROM #tblTimeOutsRpt
			ORDER BY [Day-Hour] DESC;
	END
	IF @iBitMask & 1024 != 0
	BEGIN
		INSERT INTO #tblVaePluginRpt ([Name],Trans,MinVae,AvgVae,MaxVae,StdedpVae,MinFraud
			,AvgFraud,MaxFraud,StdedpFraud,MinRtla,AvgRtla,MaxRtla,StdedpRtla)
		SELECT 'PluginRpt',Count(1),MIN(VaeBriskInMs),AVG(VaeBriskInMs),MAX(VaeBriskInMs),STDEVP (VaeBriskInMs),MIN(FraudInMs)
			,AVG(FraudInMs),MAX(FraudInMs),STDEVP (FraudInMs),MIN(RtlaInMs),AVG(RtlaInMs),MAX(RtlaInMs),STDEVP (RtlaInMs)
		FROM [ValidBankLogging].[dbo].[TransactionPluginLogCalc] WITH (READUNCOMMITTED) 
		WHERE MaxDateSubmitted between @dtTimeOuts and @dtTimeOuts2;
		IF EXISTS (SELECT 'X' FROM #tblVaePluginRpt)
			SELECT [Name],Trans,MinVae,AvgVae,MaxVae,StdedpVae
				,MinFraud,AvgFraud,MaxFraud,StdedpFraud
				,MinRtla,AvgRtla,MaxRtla,StdedpRtla
			FROM #tblVaePluginRpt;
	END
	IF @iBitMask & 2048 != 0
	BEGIN
		INSERT INTO #tblActualDBTimeRpt([Name],DBRequestInMs,RequestInMs,ConfirmInMS,IFATimingId,ProcessKey
			,SchemaName,ObjectName, Msg, Microseconds, DateExecuted, DateActivated)
		SELECT 'ActualDBTimeRpt',it.DBRequestInMs,tt.RequestInMs,tt.ConfirmInMS,i.IFATimingId,i.ProcessKey
			,i.SchemaName,i.ObjectName,i.Msg,i.Microseconds,i.DateExecuted,i.DateActivated
		FROM [dbo].[IFATiming] i
		INNER JOIN  #tblTCLRpt tt on i.ProcessKey = tt.TransactionKey
		INNER JOIN (SELECT ProcessKey, datediff(millisecond,min(DateExecuted),max(DateExecuted)) as DBRequestInMs
					FROM [dbo].[IFATiming] i0
					INNER JOIN #tblTCLRpt t0 on i0.ProcessKey = t0.TransactionKey
					WHERE i0.ObjectName = 'uspProcessRequestDeux'
					GROUP BY i0.ProcessKey,i0.ObjectName) it on tt.TransactionKey = it.ProcessKey
		WHERE (RequestInMs > @iMsThreshold 
				OR ConfirmInMs > @iMsThreshold)
		ORDER BY ProcessKey, DateExecuted, IFATimingId;
	
		INSERT INTO #tblItem(ItemId,TransactionKey) 
		SELECT tk.TransactionId,tk.TransactionKey 
		FROM [ifa].[TransactionKey] tk with (readuncommitted) 
		INNER JOIN (SELECT RTRIM(TransactionKey)+'01' as TransactionKey 
					FROM #tblTCLRpt
					GROUP BY RTRIM(TransactionKey)+'01') tkd on tk.TransactionKey =tkd.TransactionKey;

		INSERT INTO #tblItemTimingRpt([Name],TimeMs,ItemId,TransactionKey)
		SELECT 'ItemTimingRpt',DATEDIFF(ms,MIN(r.DateCompleted),MAX(r.DateCompleted)), r.ItemId, i.TransactionKey
		FROM [riskprocessing].[RPResult] r WITH (READUNCOMMITTED) 
		INNER JOIN #tblItem i on r.ItemId = i.ItemId 
		GROUP BY r.ItemId, i.TransactionKey;
		IF EXISTS (SELECT 'X' FROM #tblActualDBTimeRpt)
			SELECT [Name],DBRequestInMs,RequestInMs,ConfirmInMS,IFATimingId,ProcessKey
				,SchemaName,ObjectName, Msg, Microseconds, DateExecuted, DateActivated
			FROM #tblActualDBTimeRpt
			ORDER BY ProcessKey, DateExecuted, IFATimingId;
		IF EXISTS (SELECT 'X' FROM #tblItemTimingRpt)
			SELECT [Name],TimeMs,ItemId,TransactionKey
			FROM #tblItemTimingRpt
			ORDER BY TransactionKey;
	END
	IF  @iBitMask & 4096 != 0
	BEGIN
		INSERT INTO #tbl5MinuteActivity ([Name],Cnt,[Hour],[Minute],Mobile)
		SELECT '5MinuteActivity',COUNT(1),DATEPART(hh,p.DateActivated),DATEPART(mi,p.DateActivated) 
			,CASE WHEN p.OrgId = 100019 THEN 1 ELSE 0 END
		FROM [ifa].[Process] p WITH (READUNCOMMITTED) 
		WHERE p.DateActivated > @dt5min
		GROUP BY datepart(hh,p.DateActivated),datepart(mi,p.DateActivated),CASE WHEN p.OrgId = 100019 THEN 1 ELSE 0 End
		IF EXISTS (SELECT 'X' FROM #tbl5MinuteActivity)
			SELECT [Name],Cnt,[Hour],[Minute],Mobile
			FROM #tbl5MinuteActivity;
	END
	IF @iBitMask & 8192 != 0
		SELECT 'QueueActivityRpt' as 'Name',Src,TransactionKey, DateSubmitted, DateActivated
		FROM [ValidBankLogging].[dbo].[ufnQueueRpt]();

END

