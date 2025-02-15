USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspMainIFAHourlyReport
	Created By: Larry Dugger
	Description: Retrieve several measurements related to Transaction Processing, 
		for the preceding hour, and a day summary

	Tables: [dbo].[TransactionLog]
		,[IFA].[organization].[Org]
	
	History:
		2017-05-24 - LBD - Created
		2017-06-20 - LBD - Modified, added the Adoption Rate
		2017-06-22 - LBD - Modified, added RecipientList
		2017-07-26 - LBD - Modified, added full day totals, from BC (Bank Cutoff)
		2018-07-13 - LBD - Modified, split into OrgChannelName...
		2019-05-30 - LBD - Modified, updated to use Coalesce reference
		2019-10-14 - LBD - Modified, added HEB (42)
		2019-10-17 - LBD - Modified, corrected reference to ItemActivity for 
			RuleBreaks (which is not kept upto date)
		2019-12-09 - LBD - Modified, exclude Deluxe and FirstData Coalesces, verified
			this will work for TDB
		2020-04-15 - LBD - Added Deluxe 'push pay only' CCF1955
		2020-12-03 - LBD - Corrected 'reportable' orgs collection (coalesce dimension is 
			no longer being used)
		2020-12-29 - LBD - Restructure, consolidating and formating.
		2020-01-19 - LBD - Use [organization].[OrgCondensed] instead of [dbo].[UtilityOrg]
		2025-01-13 - LXK - Replaced table variables with local temp tables
****************************************************************************************/
ALTER     PROCEDURE [ifa].[uspMainIFAHourlyReportDeluxe](
	@pnvRecipientsList NVARCHAR(512) = 'valid.exe@validsystems.net'
)AS
BEGIN
	drop table if exists #IFAHourlyReportDeluxeItem
	CREATE table #IFAHourlyReportDeluxeItem (
		ProcessId bigint,
		OrgId int,
		ItemId bigint,
		RuleBreak nvarchar(25),
		ClientAcceptedId int,
		OrgChannelName nchar(6),
		ReportGroup nchar(3),
		DateActivated datetime2(7)
		);
	drop table if exists #IFAHourlyReportDeluxeSummary
	create table #IFAHourlyReportDeluxeSummary(
		DPassCount int, 
		DFailCount int, 
		DAdoptionCount int, 
		DPassRate decimal(6,2),
		DTranCnt int, 
		DPerMin decimal(6,2)
		,HPassCount int, 
		HFailCount int, 
		HAdoptionCount int, 
		HPassRate decimal(6,2),
		HTranCnt int, 
		HPerMin decimal(6,2)
		,OrgChannelName nchar(6), 
		ReportGroup nchar(3)
		);
	drop table if exists #IFAHourlyReportDeluxeOrgChannelName
	create table #IFAHourlyReportDeluxeOrgChannelName(
		OrgId int primary key, 
		OrgTypeId int,
		ExternalCode nvarchar(50), 
		OrgChannelName nchar(6), 
		ReportGroup nchar(3));

	DECLARE @dtDate datetime = Getdate()	
		,@iClientAcceptedId int = [common].[ufnClientAccepted]('Accepted')
		,@nvProfileName sysname = 'SSDB-PRDTRX01'
		,@nvFrom nvarchar(4000) = 'DBSupport@ValidAdvantage.com'
		,@nvHBody nvarchar(max) = ''
		,@nvDBody nvarchar(max) = ''
		,@nvSBody nvarchar(max) = ''
		,@nvSubject nvarchar(4000) = 'Hourly Activity w ClientCutoffSum From '
		,@tBankCutoffTime time = '21:00'
		,@nvBankCutoffTime nvarchar(25) = '20:59:59.997' --wierd, but works
		,@dtThisDay datetime2(7)
		,@dtStartDate datetime2(7)
		,@dtEndDate datetime2(7) = SYSDATETIME()
		,@biStartProcessId bigint
		,@biEndProcessId bigint
		,@biStartItemId bigint
		,@biEndItemId bigint
		,@fMinutesPassed float;

	--REFRESH reference table
	IF EXISTS (SELECT 'X' FROM [organization].[OrgCondensed] WHERE DateActivated < getdate()-1) 
		EXECUTE [organization].[uspLoadOrgCondensed];

	SET @dtStartDate = DATEADD(hour,-1,@dtEndDate);
	--Did we pass Start of BankCutoff?
	--Since it happens on the hour and the prior hour needs to be adjusted for...
	IF CONVERT(TIME,GETDATE()) >= dateadd(hour,1,@tBankCutoffTime)
		SET @dtThisDay = CONVERT(datetime2(7),CONVERT(DATETIME,CONVERT(DATE,getdate())) + CONVERT(DATETIME,@nvBankCutoffTime));
	ELSE
		SET @dtThisDay = CONVERT(datetime2(7),CONVERT(DATETIME,CONVERT(DATE,getdate()-1)) + CONVERT(DATETIME,@nvBankCutoffTime));

	SET @nvSubject = @nvSubject +CONVERT(nvarchar(16),@dtStartDate,121) + ' to '+ CONVERT(nvarchar(16),@dtEndDate,121)

	INSERT #IFAHourlyReportDeluxeOrgChannelName(OrgId, OrgTypeId, ExternalCode, OrgChannelName, ReportGroup)
	SELECT OrgId, OrgTypeId, ExternalCode 
		,OrgChannelName
		,CASE WHEN OrgPartnerCode IN ('FiServ','FD','ValidDirect') THEN 
			CASE WHEN OrgClientCode = 'DeluxeClnt' THEN 'DLX'
				WHEN OrgPartnerCode = 'FD' THEN 'FD'
				ELSE OrgClientCode
			END
			ELSE 'UNK'
		END as ReportGroup
	FROM [organization].[OrgCondensed]
	WHERE CASE WHEN OrgPartnerCode IN ('FiServ','FD','ValidDirect') THEN 
			CASE WHEN OrgClientCode = 'DeluxeClnt' THEN 'DLX'
				WHEN OrgPartnerCode = 'FD' THEN 'FD'
				ELSE OrgClientCode
			END
			ELSE 'UNK'
		END  in ('PNC','TDB','FTB','MTB','HEB','DLX','FD')
		AND OrgTypeId BETWEEN 16 AND 18		--keep locations, sublocations and atms only
		AND ExternalCode NOT LIKE '%Test%'	--exclude test locations
		AND ExternalCode NOT LIKE 'Dup%'	--exclude test locations
		AND ExternalCode <> 'HEB'			--exclude abberant externalcode
		AND OrgId <> 147163					--exclude deluxe pre-auth
		AND OrgChannelName IS NOT NULL;		--exclude trash locations

	INSERT INTO #IFAHourlyReportDeluxeItem(ProcessId,OrgId,ItemId,RuleBreak,ClientAcceptedId, OrgChannelName, ReportGroup, DateActivated)
	SELECT ia.ProcessId,ia.OrgId,ia.Itemid, CASE WHEN ISNULL(rbd.Code,N'0') = N'0'  THEN N'0' ELSE N'1' END as RuleBreak
		,ia.ClientAcceptedId, cc.OrgChannelName, cc.ReportGroup, ia.DateActivated
	FROM [financial].[ItemActivity] ia
	INNER JOIN #IFAHourlyReportDeluxeOrgChannelName cc on ia.OrgId = cc.OrgId
	LEFT OUTER JOIN [ifa].[RuleBreakData] rbd ON ia.ItemId = rbd.ItemId
	WHERE ia.DateActivated between @dtThisDay and @dtEndDate;

	INSERT INTO #IFAHourlyReportDeluxeItem(ProcessId,OrgId,ItemId,RuleBreak,ClientAcceptedId, OrgChannelName, ReportGroup, DateActivated)
	SELECT ia.ProcessId,ia.OrgId,ia.Itemid, CASE WHEN ISNULL(rbd.Code,N'0') = N'0'  THEN N'0' ELSE N'1' END as RuleBreak
		,ia.ClientAcceptedId, cc.OrgChannelName, cc.ReportGroup, ia.DateActivated
	FROM [retail].[ItemActivity] ia
	INNER JOIN #IFAHourlyReportDeluxeOrgChannelName cc on ia.OrgId = cc.OrgId
	LEFT OUTER JOIN [ifa].[RuleBreakData] rbd ON ia.ItemId = rbd.ItemId
	WHERE ia.DateActivated between @dtThisDay and @dtEndDate;

	INSERT INTO #IFAHourlyReportDeluxeItem(ProcessId,OrgId,ItemId,RuleBreak,ClientAcceptedId, OrgChannelName, ReportGroup, DateActivated)
	SELECT ia.ProcessId,ia.OrgId,ia.Itemid, CASE WHEN ISNULL(rbd.Code,N'0') = N'0'  THEN N'0' ELSE N'1' END as RuleBreak
		,ia.ClientAcceptedId, cc.OrgChannelName, cc.ReportGroup, ia.DateActivated
	FROM [authorized].[ItemActivity] ia
	INNER JOIN #IFAHourlyReportDeluxeOrgChannelName cc on ia.OrgId = cc.OrgId
	LEFT OUTER JOIN [ifa].[RuleBreakData] rbd ON ia.ItemId = rbd.ItemId
	WHERE ia.DateActivated between @dtThisDay and @dtEndDate;

	CREATE INDEX ix01Item ON #IFAHourlyReportDeluxeItem(OrgChannelName,ReportGroup) INCLUDE(ProcessId,OrgId,ItemId,RuleBreak,ClientAcceptedId,DateActivated);

	SET @fMinutesPassed = datediff(minute,@dtThisDay,@dtEndDate);

	INSERT INTO #IFAHourlyReportDeluxeSummary(DTranCnt,DPerMin,DPassCount,DFailCount,DAdoptionCount,HTranCnt,HPerMin,HPassCount,HFailCount,HAdoptionCount,OrgChannelName,ReportGroup)
	SELECT count(*),count(*)/(@fMinutesPassed),0,0,0,0,0,0,0,0,OrgChannelName,ReportGroup
	FROM #IFAHourlyReportDeluxeItem
	GROUP BY OrgChannelName, ReportGroup;
	UPDATE s
		SET DPassCount = c.Cnt
	FROM #IFAHourlyReportDeluxeSummary s
	INNER JOIN (SELECT COUNT(*) as Cnt, OrgChannelName, ReportGroup FROM #IFAHourlyReportDeluxeItem 
		WHERE RuleBreak = '0'
		GROUP BY OrgChannelName, ReportGroup) c on s.OrgChannelName = c.OrgChannelName 
										and s.ReportGroup = c.ReportGroup;
	UPDATE s
		SET DFailCount =  c.Cnt
	FROM #IFAHourlyReportDeluxeSummary s
	INNER JOIN (SELECT COUNT(*) as Cnt, OrgChannelName, ReportGroup
		FROM #IFAHourlyReportDeluxeItem 
		WHERE RuleBreak = '1'
		GROUP BY OrgChannelName, ReportGroup)  c on s.OrgChannelName = c.OrgChannelName 
										and s.ReportGroup = c.ReportGroup;
	UPDATE s
		SET DAdoptionCount = c.Cnt
	FROM #IFAHourlyReportDeluxeSummary s
	INNER JOIN (SELECT COUNT(*) as Cnt, OrgChannelName, ReportGroup
		FROM #IFAHourlyReportDeluxeItem 
		WHERE RuleBreak = '0'
			AND ClientAcceptedId = @iClientAcceptedId
		GROUP BY OrgChannelName, ReportGroup)  c on s.OrgChannelName = c.OrgChannelName 
										and s.ReportGroup = c.ReportGroup;
	UPDATE s
		SET DPassRate =  (s.DPassCount/((s.DPassCount+s.DFailCount)*1.0))*100.0 
	FROM #IFAHourlyReportDeluxeSummary s
	WHERE (s.DPassCount + s.DFailCount) <> 0

	--Hourly Calcs
	SET @fMinutesPassed = datediff(minute,@dtStartDate,@dtEndDate);

	UPDATE s
		SET HTranCnt = c.Cnt
			,HPerMin = c.Cnt/(@fMinutesPassed)
	FROM #IFAHourlyReportDeluxeSummary s
	INNER JOIN (SELECT COUNT(*) as Cnt, OrgChannelName, ReportGroup FROM #IFAHourlyReportDeluxeItem 
		WHERE DateActivated BETWEEN @dtStartDate and @dtEndDate
		GROUP BY OrgChannelName, ReportGroup) c on s.OrgChannelName = c.OrgChannelName 
										and s.ReportGroup = c.ReportGroup;
	UPDATE s
		SET HPassCount = c.Cnt
	FROM #IFAHourlyReportDeluxeSummary s
	INNER JOIN (SELECT COUNT(*) as Cnt, OrgChannelName, ReportGroup FROM #IFAHourlyReportDeluxeItem 
		WHERE DateActivated BETWEEN @dtStartDate and @dtEndDate
			AND RuleBreak = '0'
		GROUP BY OrgChannelName, ReportGroup) c on s.OrgChannelName = c.OrgChannelName 
										and s.ReportGroup = c.ReportGroup;
	UPDATE s
		SET HFailCount =  c.Cnt
	FROM #IFAHourlyReportDeluxeSummary s
	INNER JOIN (SELECT COUNT(*) as Cnt, OrgChannelName, ReportGroup
		FROM #IFAHourlyReportDeluxeItem 
		WHERE DateActivated BETWEEN @dtStartDate and @dtEndDate
			AND RuleBreak = '1'
		GROUP BY OrgChannelName, ReportGroup)  c on s.OrgChannelName = c.OrgChannelName 
										and s.ReportGroup = c.ReportGroup;
	UPDATE s
		SET HAdoptionCount = Cnt
	FROM #IFAHourlyReportDeluxeSummary s
	INNER JOIN (SELECT COUNT(*) as Cnt, OrgChannelName, ReportGroup
		FROM #IFAHourlyReportDeluxeItem 
		WHERE DateActivated BETWEEN @dtStartDate and @dtEndDate
			AND RuleBreak = '0'
			AND ClientAcceptedId = @iClientAcceptedId
		GROUP BY OrgChannelName, ReportGroup)  c on s.OrgChannelName = c.OrgChannelName 
										and s.ReportGroup = c.ReportGroup;
	UPDATE s
		SET HPassRate =  (s.HPassCount/((s.HPassCount+s.HFailCount)*1.0))*100.0
	FROM #IFAHourlyReportDeluxeSummary s
	WHERE (s.HPassCount + s.HFailCount) <> 0;
	
	SELECT ((HAdoptionCount*1.0)/(HPassCount*1.0))*100.00 AS HSumAR, OrgChannelName, ReportGroup
	INTO #tblHSumAR
	FROM #IFAHourlyReportDeluxeSummary
	WHERE HPassCount <> 0;

	SET @nvHBody = '<table cellpadding="2" cellspacing="2" border="2"> '+'<tr><th>Hourly</th></tr>' +
			'<table cellpadding="2" cellspacing="2" border="2"> <tr><th>Group</th><th>OrgChannelName</th><th>Pass%</th><th>TranCnt</th><th>PerMin</th><th>Adopt</th><th>Adopt%</th></tr>' + 
		replace(replace((SELECT td = s.ReportGroup +'</td><td>' +
							s.OrgChannelName +'</td><td>'+
							FORMAT(s.HPassRate, 'N', 'en-us') +'</td><td>'+ 
							CONVERT(nvarchar(10),s.HTranCnt) +'</td><td>'+ 
							FORMAT(s.HPerMin, 'N', 'en-us') +'</td><td>'+
							CONVERT(nvarchar(10),s.HAdoptionCount) +'</td><td>'+
							FORMAT(ISNULL(t.HSumAR,0.0), 'N', 'en-us')
						FROM #IFAHourlyReportDeluxeSummary as  s 
						LEFT OUTER JOIN #tblHSumAR as t on s.OrgChannelName = t.OrgChannelName
										and s.ReportGroup = t.ReportGroup
						WHERE s.HTranCnt > 0
						ORDER BY  s.ReportGroup, s.OrgChannelName
						FOR XML PATH('tr')), '&lt;', '<'), '&gt;', '>') + '</table></table>' 

	SELECT (((DAdoptionCount)*1.0)/(DPassCount)*1.0)*100.00 AS DSumAR, OrgChannelName, ReportGroup
	INTO #tblDSumAR
	FROM #IFAHourlyReportDeluxeSummary
	WHERE DPassCount <> 0;

	SET @nvDBody = '<table cellpadding="2" cellspacing="2" border="2"> '+'<tr><th>Daily</th></tr>' +
			'<table cellpadding="2" cellspacing="2" border="2"> <tr><th>Group</th><th>OrgChannelName</th><th>Pass%</th><th>TranCnt</th><th>PerMin</th><th>Adopt</th><th>Adopt%</th></tr>' + 
		replace(replace((SELECT td = s.ReportGroup +'</td><td>' + 
							s.OrgChannelName +'</td><td>'+ 
							FORMAT(s.DPassRate, 'N', 'en-us') +'</td><td>'+ 
							CONVERT(nvarchar(10),s.DTranCnt) +'</td><td>'+ 
							FORMAT(s.DPerMin, 'N', 'en-us') +'</td><td>'+ 
							CONVERT(nvarchar(10),s.DAdoptionCount) +'</td><td>'+
							FORMAT(ISNULL(t.DSumAR,0.0), 'N', 'en-us')
						FROM #IFAHourlyReportDeluxeSummary as s 
						LEFT OUTER JOIN #tblDSumAR as t on s.OrgChannelName = t.OrgChannelName
										and s.ReportGroup = t.ReportGroup
						ORDER BY  s.ReportGroup, s.OrgChannelName
						FOR XML PATH('tr')), '&lt;', '<'), '&gt;', '>') + '</table>'

	SET @nvSBody = '<table cellpadding="2" cellspacing="2" border="2">'+'<tr><th>DailyTotals</th></tr>' +
			'<table cellpadding="2" cellspacing="2" border="2"> <tr><th>Group</th><th>Pass%</th><th>TranCnt</th><th>PassCnt</th><th>PerMin</th><th>Adopt</th><th>Adopt%</th></tr>' + 
		replace(replace((SELECT td = ReportGroup +'</td><td>' +
							FORMAT(s.SumPPercent, 'N', 'en-us') +'</td><td>' +
							CONVERT(nvarchar(10),s.SumTC) +'</td><td>' +
							CONVERT(nvarchar(10),s.SumPC) +'</td><td>' +
							FORMAT((s.SumPC*1.0)/datediff(minute,@dtThisDay,@dtEndDate), 'N', 'en-us') +'</td><td>' +
							CONVERT(nvarchar(10),s.SumAC) +'</td><td>' +
							FORMAT(s.SumAR, 'N', 'en-us') 
						FROM (SELECT CASE WHEN SUM(DPassCount)+SUM(DFailCount) <> 0 
											THEN (SUM(DPassCount)/((SUM(DPassCount)+SUM(DFailCount))*1.0))*100.0 
										ELSE 0 END as SumPPercent
								,SUM(DTranCnt) as SumTC
								,SUM(DPassCount) as SumPC
								,SUM(DAdoptionCount) as SumAC
								,CASE WHEN SUM(DPassCount) <> 0 THEN ((SUM(DAdoptionCount)*1.0)/(SUM(DPassCount)*1.0)*100.00) ELSE 0 END as SumAR
								,'ALL' as ReportGroup
							FROM #IFAHourlyReportDeluxeSummary) as s
		FOR XML PATH('tr')), '&lt;', '<'), '&gt;', '>') + '</table></table>'

	SET @nvHBody = @nvHBody + '
	'+@nvDBody+'
	'+@nvSBody;

	--Sending Mail
	EXEC msdb.dbo.sp_send_dbmail 
		 @profile_name = @nvProfileName
		,@recipients = @pnvRecipientsList
		,@from_address = @nvFrom
		,@body = @nvHBody
		,@body_format = 'HTML'
		,@subject = @nvSubject
		,@importance = 'Low';

END
