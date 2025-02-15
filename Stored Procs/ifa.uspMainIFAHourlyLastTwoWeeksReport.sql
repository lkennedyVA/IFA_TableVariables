USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/****************************************************************************************
	Name: uspMainIFAHourlyLastTwoWeeksReport
	Created By: Larry Dugger
	Description: Retrieve several measurements related to Transaction Processing, 
		for the preceding hour, and a day summary

	Tables: [dbo].[TransactionLog]
		,[IFA].[organization].[Org]
	
	History:
		2018-09-17 - LBD - Created
		2025-01-13 - LXK - Replaced table variables with local temp tables
*****************************************************************************************/
ALTER   PROCEDURE [ifa].[uspMainIFAHourlyLastTwoWeeksReport](
	 @piOrgId INT = 100009
)AS
BEGIN

	drop table if exists #IFAHourlyLast2wksReportProcess
	DECLARE #IFAHourlyLast2wksReportProcess table(
		ProcessId bigint, 
		Channel nvarchar(50), 
		DtHour nvarchar(10)
		); 
	drop table if exists #IFAHourlyLast2wksReportItems
	DECLARE #IFAHourlyLast2wksReportItems table(
		ItemId bigint, 
		RuleBreak nvarchar(25), 
		ClientAcceptedId int, 
		DateActivated datetime2(7), 
		Channel nvarchar(50), 
		DtHour nvarchar(10)
		); 
	drop table if exists #IFAHourlyLast2wksReportCount
	DECLARE #IFAHourlyLast2wksReportCount table (
		DtHour nvarchar(10), 
		Channel nvarchar(50), 
		TtlCount int, 
		Rate float, 
		PassCount int, 
		FailCount int, 
		AdoptionCount int
		);

	DECLARE @dtDate datetime = Getdate()	
		,@iClientAcceptedId int = [common].[ufnClientAccepted]('Accepted')
		,@dtStartDate datetime2(7) = dateadd(hour,-360, SYSDATETIME()) --2 weeks
		,@dtEndDate datetime2(7) = dateadd(day,-1,SYSDATETIME())
		,@iOrgId int = @piOrgId;

	insert into #IFAHourlyLast2wksReportProcess(ProcessId, Channel, DtHour)
	select ProcessId, [common].[ufnOrgChannelName](OrgId),replace(replace(convert(nvarchar(13),DateActivated,121),'-',''),' ','')
	from [ifa].[Process] with (readuncommitted) 
	where DateActivated between @dtStartDate and @dtEndDate
		and [common].[ufnOrgClientId](OrgId) = @iOrgId;
	
	insert into #IFAHourlyLast2wksReportItems(ItemId,RuleBreak,ClientAcceptedId,DateActivated,Channel,DtHour)
	select i.Itemid, i.RuleBreak, i.ClientAcceptedId, DateActivated, Channel, p.DtHour
	from [ifa].[Item] i with (readuncommitted) 
	inner join #IFAHourlyLast2wksReportProcess p on i.ProcessId = p.Processid;

	INSERT INTO #IFAHourlyLast2wksReportCount(DtHour, TtlCount, Rate, Channel)
	SELECT DtHour
		,count(*)
		,count(*)/(60.0)
		,Channel
	FROM #IFAHourlyLast2wksReportItems
	GROUP BY Channel, DtHour

	update c
	set PassCount = PCount
	from #IFAHourlyLast2wksReportCount c
	inner join (select Count(*) as PCount, Channel, DtHour from #IFAHourlyLast2wksReportItems 
				WHERE RuleBreak = '0'
				GROUP BY Channel, DtHour) as i on c.DtHour = i.DThour
										and c.Channel = i.Channel;

	update c
	set AdoptionCount = ACount
	from #IFAHourlyLast2wksReportCount c
	inner join (select Count(*) as ACount, Channel, DtHour from #IFAHourlyLast2wksReportItems 
				WHERE RuleBreak = '0'
					AND ClientAcceptedId = @iClientAcceptedId
				GROUP BY Channel, DtHour) as i on c.DtHour = i.DThour
										and c.Channel = i.Channel;

	update c
	set FailCount = FCount
	from #IFAHourlyLast2wksReportCount c
	inner join (select Count(*) as FCount, Channel, DtHour from #IFAHourlyLast2wksReportItems 
				WHERE RuleBreak = '1'
				GROUP BY Channel, DtHour) as i on c.DtHour = i.DThour
										and c.Channel = i.Channel;

	SELECT DtHour, Channel, TtlCount, Rate as 'Rate/Min', PassCount, FailCount, AdoptionCount, PassCount/(TtlCount*1.0) as PassPercent, AdoptionCount/(TtlCount*1.0) as AdoptPercent
	FROM #IFAHourlyLast2wksReportCount
END
