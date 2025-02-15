USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspMainIFAMeasurements
	Created By: Larry Dugger
	Date: 2016-07-19
	Description: Retrieve many measurements related to Transaction Processing
		limit your Date range to 1 hour max, a few minutes for most. 

	Tables: [dbo].[TransactionLog]
		,[IFA].[organization].[Org]
	
	History:
		2017-04-28 - LBD - Created
		2025-01-13 - LXK - Replaced table variables with local temp tables
*****************************************************************************************/
ALTER PROCEDURE  [ifa].[uspMainIFAMeasurements](
	 @pdtStartDate DATETIME2(7) = NULL
	,@pdtEndtDate DATETIME2(7) = NULL
	,@pnvOrgName nvarchar(50) = 'PNC Bank'
)
AS
BEGIN
	drop table if exists #MainIFAMeasurements
	create table #MainIFAMeasurements(
		[Process Count] int, 
		[RPResult Count] int,
		[IFATiming Count] int,
		[TimeSlice Hour:Min] nvarchar(5),
		[Item Count] int
		);
	drop table if exists #MainIFAMeasurementsProcessKey
	create table #MainIFAMeasurementsProcessKey(
		ProcessKey nvarchar(25) primary key, 
		ProcessId bigint
		);
	drop table if exists #MainIFAMeasurementsTiming
	create table #MainIFAMeasurementsTiming(
		IFATimingId bigint, 
		ProcessKey nvarchar(25), 
		SchemaName nvarchar(128), 
		ObjectName nvarchar(128), 
		Msg nvarchar(255), 
		Microseconds bigint, 
		DateExecuted datetime2(7), 
		DateActivated datetime2(7)
		);
	drop table if exists #MainIFAMeasurements2
	create table #MainIFAMeasurements2(
		TranCnt int,
		MinMS int,
		AvgMs int,
		MaxMs int,
		StdevMs int,
		ObjectName nvarchar(128),
		Step nvarchar(10)
		);
	drop table if exists #MainIFAMeasurementsSummary
	create table #MainIFAMeasurementsSummary(
		OrgName nvarchar(50), 
		InfoDesc nvarchar(255), 
		TranCount int, 
		MinTimeMS bigint, 
		MaxTimeMS bigint, 
		AvgTimeMS bigint, 
		StDevTimeMS float, 
		CntOvrAvg int, 
		DtRange nvarchar(100), 
		DateExecuted datetime2(7)
		);
	declare @dtStartDate datetime = @pdtStartDate--'2017-04-27 16:00'
		,@dtEndDate datetime = @pdtEndtDate--'2017-04-27 17:00'
		,@biStartProcessId bigint
		,@biEndProcessId bigint
		,@biStartItemId bigint
		,@biEndItemId bigint;
	IF ISNULL(@pdtStartDate,'') = ''
	BEGIN
		SET @dtStartDate = DATEADD(minute,-61,SYSDATETIME());
		SET @dtEndDate = DATEADD(minute,-1,SYSDATETIME());
	END
	ELSE IF ISNULL(@pdtEndtDate,'') = ''
		SET @dtEndDate = DATEADD(minute,-1,@pdtStartDate);

	SELECT @biStartProcessId = min(ProcessId)
		,@biEndProcessId = max(ProcessId)
	from [ifa].[Process] with (readuncommitted) 
	where DateActivated between @dtStartDate and dateadd(minute,1,@dtEndDate)
	insert into #MainIFAMeasurementsProcessKey(ProcessKey, ProcessId)
	select ProcessKey, ProcessId
	from [ifa].[Process] with (readuncommitted) 
	where ProcessId between @biStartProcessId and @biEndProcessId;
	select @biEndItemId = max(ItemId), @biStartItemId = min(ItemId)
	from [ifa].[Item] with (readuncommitted) 
	where ProcessId between @biStartProcessId and @biEndProcessId;
	declare @dt datetime = @dtStartDate;
	select  'Pass/Fail counts' as Title, count(*) as cnt, RuleBreak, RuleBreakResponse
	from [ifa].[Item] with (readuncommitted) 
	where ItemId between @biStartItemId and @biEndItemId
	group by RuleBreak, RuleBreakResponse

	while @dt <= @dtEndDate
	begin
		insert into #MainIFAMeasurements([Process Count],[RPResult Count],[IFATiming Count],[Item Count],[TimeSlice Hour:Min] )
		select p.Cnt,r.Cnt,i.Cnt,i2.Cnt,p.Descr
		from (select count(*) as Cnt,SUBSTRING(CONVERT(nvarchar(25),@dt,14),1,5) as Descr
				from [ifa].[Process] with (readuncommitted) 
				where DateActivated between @dt and dateadd(minute,1,@dt)) p
		inner join (select count(*) as Cnt,SUBSTRING(CONVERT(nvarchar(25),@dt,14),1,5) as Descr
					from [riskprocessing].[RPResult] with (readuncommitted) 
					where DateActivated between @dt and dateadd(minute,1,@dt)) r on p.Descr = r.Descr
		inner join (select count(*) as Cnt,SUBSTRING(CONVERT(nvarchar(25),@dt,14),1,5) as Descr
				from [dbo].[IFATiming] with (readuncommitted) 
				where DateExecuted between @dt and dateadd(minute,1,@dt)) i on p.Descr = i.Descr
		inner join (select count(*) as Cnt,SUBSTRING(CONVERT(nvarchar(25),@dt,14),1,5) as Descr
				from [ifa].[Item] with (readuncommitted) 
				where DateActivated between @dt and dateadd(minute,1,@dt)) i2 on p.Descr = i2.Descr;
		set @dt = dateadd(minute,1,@dt);
	end

	select 'Activity/Minute' as Title
		,[Process Count]
		,[RPResult Count]
		,[IFATiming Count]
		,[TimeSlice Hour:Min] 
		,[Item Count]
	from #MainIFAMeasurements;

	select 'Total Count' as Title
		,sum([Process Count]) as ttl
		,sum([Process Count])/(count(*)*1.0) as 'Rate/Min' 
	from #MainIFAMeasurements;

	---select max(DateActivated) from [ifa].[Process]
	insert into #MainIFAMeasurementsTiming(ProcessKey, ObjectName, DateExecuted)
	select i.ProcessKey, i.ObjectName, i.DateExecuted
	from dbo.IFATiming i with (readuncommitted) 
	inner join #MainIFAMeasurementsProcessKey pk on i.ProcessKey = pk.ProcessKey;

	insert into #MainIFAMeasurements2(TranCnt,MinMS,AvgMs,MaxMs,StdevMs,ObjectName,Step)
	select count(*),min(datediff(MILLISECOND,gp.minde,gp.maxde)) minMs
		,avg(datediff(MILLISECOND,gp.minde,gp.maxde)) avgMs
		,max(datediff(MILLISECOND,gp.minde,gp.maxde)) maxMs
		,stdev(datediff(MILLISECOND,gp.minde,gp.maxde)) stdevMs
		,gp.objectname
		,CASE WHEN gp.objectname = 'uspProcessRequest' then '1'
			WHEN gp.objectname = 'uspItemInsertOut' then '2'
			WHEN gp.objectname = 'uspProcessRiskControl' then '3'
			WHEN gp.objectname = 'ufnTraverseLadder' then '4'
			WHEN gp.objectname = 'uspProcessConfirmationRequest' then '5'
			WHEN gp.objectname = 'uspLoadField' then '6'
			WHEN gp.objectname = 'uspLoadStuff' then '7'
			END
	from (select min(DateExecuted) as minde,max(DateExecuted) as maxde,p.ProcessId,it.objectname
			from [ifa].[Process] p with (readuncommitted,index=ux01Process)
			inner join #MainIFAMeasurementsTiming it on p.ProcessKey = it.ProcessKey
			where p.Processid between @biStartProcessId and @biEndProcessId
			group by p.Processid,it.objectname
			having datediff(MILLISECOND,min(DateExecuted),max(DateExecuted)) <= 2000
	) gp 
	group by gp.objectname
	select 'Activity <= 2 Seconds' as Title,* from #MainIFAMeasurements2 order by Step;

	select 'Activity > 2 Seconds' as Title
		,datediff(MILLISECOND,min(DateExecuted),max(DateExecuted)) as ActivityMS
		,ItemCnt
		,p.ProcessId
		,it.ObjectName
	from [ifa].[Process] p with (readuncommitted, index=ux01Process)
	inner join #MainIFAMeasurementsTiming it on p.ProcessKey = it.ProcessKey
	inner join (select Count(1) as ItemCnt, pk.ProcessId 
				from [ifa].[Item] i with (readuncommitted)
				inner join #MainIFAMeasurementsProcessKey pk on i.ProcessId = pk.ProcessId
				group by pk.ProcessId) ipk on p.ProcessId = ipk.ProcessId
	where p.Processid between @biStartProcessId and @biEndProcessId
	group by p.Processid,ipk.ItemCnt,it.objectname
	having datediff(MILLISECOND,min(DateExecuted),max(DateExecuted)) > 2000;

	select 'Distinct Paths' as Title
		,count(*) as 'Count'
		,[Path]
	from [riskprocessing].[ufnDistinctRiskPaths](@biStartItemId,@biEndItemId) 
	--where [Path#] = '1' 
	group by [Path];

	select 'TransactionLog Counts' as Title
		,count(*) Cnt
		,max(dateSubmitted) maxdate 
	from [ValidBankLogging].[dbo].[TransactionLog] WITH (READUNCOMMITTED) 
	where DateSubmitted > @dtStartDate;

	select 'TransactionLog Ratio' as Title, 
		count(*)/(select sum([Process Count])*1.0 
					from #MainIFAMeasurements) as LogRatio 
	from [ValidBankLogging].[dbo].[TransactionLog] WITH (READUNCOMMITTED)
	where DateSubmitted > @dtStartDate;

	insert into #MainIFAMeasurementsSummary(OrgName, InfoDesc, TranCount, MinTimeMS, MaxTimeMS, AvgTimeMS, StDevTimeMS, CntOvrAvg, DtRange, DateExecuted)
	execute [ValidbankLogging].[utility].[uspTransactionTimeSummaryRange] @dtStartDate,@dtEndDate,@pnvOrgName;

	select 'TransactionLog Summary' as Title, *
	from #MainIFAMeasurementsSummary;

END
