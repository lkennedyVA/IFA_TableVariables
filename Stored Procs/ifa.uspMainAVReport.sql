USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspMainAVReport
	Created By: Larry Dugger
	Description: Retrieve several measurements related to Transaction Processing, 
		for the preceding day, and a month summary

	Tables:  [ValidBank].[accountverification].[Transaction]
		,[ValidBank].[dbo].[EN_CUST_BANK]
	
	History:
		2023-06-12 - LBD - Created
		2025-01-09 - LXK - Replaced table variable with local temp table
****************************************************************************************/
ALTER   PROCEDURE [ifa].[uspMainAVReport](
	@pnvRecipientsList NVARCHAR(512) = 'valid.exe@validsystems.net'
)AS
BEGIN
	SET NOCOUNT ON

	--DROP TABLE IF EXISTS #tblAVClients;
	drop table if exists #tblMainAVReport;
	create table #tblMainAVReport( 
		BankName nvarchar(50), 
		AVCount int, 
		ReportGroup nchar(10)
		);
	DECLARE @iClientAcceptedId int = [common].[ufnClientAccepted]('Accepted')
		,@nvProfileName sysname = 'SSDB-PRDTRX01'
		,@nvFrom nvarchar(4000) = 'DBSupport@ValidAdvantage.com'
		,@nvLast24Body nvarchar(max) = ''
		,@nvMonthBody nvarchar(max) = ''
		,@dtStartDate datetime2(7) = DATEADD(HOUR,-24,GETDATE())
		,@dtEndDate datetime2(7) = GETDATE();
	DECLARE @dtMonthStart date = DATEADD(MONTH, DATEDIFF(MONTH, 0, @dtEndDate), 0)
		,@nvSubject nvarchar(4000) = 'Account Verification Counts at '+ CONVERT(nvarchar(16),@dtStartDate,121);
		
	--REFRESH reference table
	IF EXISTS (SELECT 'X' FROM [organization].[OrgCondensed] WHERE DateActivated < getdate()-1) 
		EXECUTE [organization].[uspLoadOrgCondensed];

	INSERT INTO #tblMainAVReport(BankName,AVCount,ReportGroup)
	SELECT b.BANK_NAME,COUNT(t.[TransactionID]) as 'AVCount', 'Last24' as 'Freq'
	FROM [ValidBank].[accountverification].[Transaction] t
	INNER JOIN [ValidBank].[dbo].[EN_CUST_BANK] b ON t.BankID = b.BANK_ID
	WHERE b.BANK_ID IN (172,106,141,168)
	AND t.[InitialDate] between @dtStartDate and @dtEndDate GROUP BY b.BANK_NAME;
	INSERT INTO #tblMainAVReport(BankName,AVCount,ReportGroup)
	Select b.BANK_NAME,COUNT(t.[TransactionID]) as 'AVCount', 'Month' as 'Freq'
	FROM [ValidBank].[accountverification].[Transaction] t
	INNER JOIN [ValidBank].[dbo].[EN_CUST_BANK] b ON t.BankID = b.BANK_ID
	WHERE b.BANK_ID IN (172,106,141,168)
	AND t.[InitialDate] between @dtMonthStart and @dtEndDate GROUP BY b.BANK_NAME;

	--select * from #tblMainAVReport

	SET @nvLast24Body = '<table cellpadding="2" cellspacing="2" border="2"> '+'<tr><th>Last24hr</th></tr>' +
			'<table cellpadding="2" cellspacing="2" border="2"> <tr><th>Group</th><th>AVCnt</th></tr>' + 
		replace(replace((SELECT td = s.BankName +'</td><td>' +
							CONVERT(NVARCHAR(10),s.AVCount)
						FROM #tblMainAVReport as  s 
						WHERE s.ReportGroup = 'Last24'
						ORDER BY  s.ReportGroup
						FOR XML PATH('tr')), '&lt;', '<'), '&gt;', '>') + '</table></table>' 

	SET @nvMonthBody = '<table cellpadding="2" cellspacing="2" border="2"> '+'<tr><th>CurrentMonth</th></tr>' +
			'<table cellpadding="2" cellspacing="2" border="2"> <tr><th>Group</th><th>AVCnt</th></tr>' + 
		replace(replace((SELECT td = s.BankName +'</td><td>' +
							CONVERT(NVARCHAR(10),s.AVCount)
						FROM #tblMainAVReport as s 
						WHERE s.ReportGroup = 'Month'
						ORDER BY  s.ReportGroup
						FOR XML PATH('tr')), '&lt;', '<'), '&gt;', '>') + '</table></table>' 

	SET @nvLast24Body = @nvLast24Body + '
	'+@nvMonthBody;

	--Sending Mail
	EXEC msdb.dbo.sp_send_dbmail 
		 @profile_name = @nvProfileName
		,@recipients = @pnvRecipientsList
		,@from_address = @nvFrom
		,@body = @nvLast24Body
		,@body_format = 'HTML'
		,@subject = @nvSubject
		,@importance = 'Low';

END
