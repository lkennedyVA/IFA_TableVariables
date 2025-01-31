USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [uspIFATransactionTimingAlerts]
	CreatedBy: Larry Dugger
	Date: 2017-04-26
	Description: Emails Transaction Timing Alerts
		Current Alerts:
			Item tran time greater than 1.5sec - Prod IFA Severity 1
			Item average tran time greated than 349 millisecs - Prod IFA Severity 2

	History:
		2017-04-26 - LBD - Created
		2018-06-25 - LBD - Modified, added central ProfileName
		2023-06-30 - CBS - VALID-1099: Replacing LDugger@validsystems.net with dbmonitoralerts@validsystems.net
****************************************************************************************/
ALTER   PROCEDURE [ifa].[uspIFATransactionTimingAlerts]
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @ProcessKey table (ProcessKey nvarchar(25) primary key, ProcessId bigint);
	DECLARE @IFATiming table(ProcessId bigint,IFATimingId bigint, ProcessKey nvarchar(25) 
		,SchemaName nvarchar(128), ObjectName nvarchar(128), Msg nvarchar(255), Microseconds bigint
		,DateExecuted datetime2(7), DateActivated datetime2(7));
	DECLARE @IFATiming2 table(ProcessId bigint, MicroSeconds bigint);
	declare @dtStartDate datetime = dateadd(minute,-1,getdate())
		,@dtEndDate datetime = dateadd(minute,-11,getdate())
		,@nvtableHTML nvarchar(max)
		,@nvProfileName nvarchar(128) = 'SSDB-PRDTRX01';
	DECLARE @tStartTime time = @dtStartDate
		,@tEndTime time = @dtEndDate;

	--GET the participants
	INSERT INTO @ProcessKey(ProcessId,ProcessKey)
	SELECT ProcessId,ProcessKey 
	FROM [ifa].[Process] WITH (READUNCOMMITTED)
	WHERE DateActivated between @dtStartDate and dateadd(minute,1,@dtEndDate)
	--BASE Timing
	INSERT INTO @IFATiming(ProcessId, ProcessKey, ObjectName, DateExecuted)
	SELECT pk.ProcessId, i.ProcessKey, i.ObjectName, i.DateExecuted
	FROM [dbo].[IFATiming] i WITH (READUNCOMMITTED)
	INNER JOIN @ProcessKey pk on i.ProcessKey = pk.ProcessKey;
	--SUMmary Timing
	INSERT INTO @IFATiming2(ProcessId,MicroSeconds)
	select ProcessId,datediff(microsecond,Min(DateExecuted),Max(DateExecuted)) 
	from @IFATiming
	where ObjectName in ('uspProcessRequest','uspProcessConfirmationRequest')
	group by ProcessKey,ProcessId;

	IF EXISTS (SELECT 'X' FROM @IFATiming2
							WHERE MicroSeconds> 150000)
	BEGIN
		SET @nvtableHTML = N'';
		SET @nvtableHTML =
			N'<H1>Total Trans Greater than 1500Ms, '+CONVERT(NVARCHAR(5),@tStartTime)+' - '+CONVERT(NVARCHAR(5),@tEndTime)+'</H>' +
			N'<table border="1">' + 
			N'<tr><th>ProcessId</th><th>Milliseconds</th>' +  
			CONVERT(NVARCHAR(MAX),(SELECT td = ProcessId,'',
										td = MicroSeconds/1000
								FROM @IFATiming2
								WHERE MicroSeconds> 1500000
								order by MicroSeconds desc
								FOR XML PATH ('tr'), TYPE
								)
			) +
			N'</table>';
		EXEC msdb.dbo.sp_send_dbmail
			@profile_name = @nvProfileName,
			@recipients = 'dbmonitoralerts@validsystems.net;MRing@validsystems.net;LWhiting@Validadvantage.com',
			@body = @nvtableHTML,
			@body_format = 'HTML',
			@subject = 'Prod IFA Severity 1';
	END
	IF EXISTS (SELECT 'X' FROM @IFATiming2 
				HAVING AVG(Microseconds) > 349000)
	BEGIN
		SET @nvtableHTML = N'';
		SET @nvtableHTML =
			N'<H1>Average Trans Greater than 349Ms, '+CONVERT(NVARCHAR(5),@tStartTime)+' - '+CONVERT(NVARCHAR(5),@tEndTime)+'</H>' +
			N'<table border="1">' + 
			N'<tr><th>TranCountChkd</th><th>AvgMilliseconds</th>' +							 
			CONVERT(NVARCHAR(MAX),(SELECT td = Count(*),'',
										td = AVG(Microseconds/1000)
									FROM @IFATiming2
									HAVING AVG(Microseconds) > 349000
									FOR XML PATH ('tr'), TYPE
									)
			) +
			N'</table>';
		EXEC msdb.dbo.sp_send_dbmail
			@profile_name = @nvProfileName,
			@recipients = 'dbmonitoralerts@validsystems.net;MRing@validsystems.net;LWhiting@Validadvantage.com',
			@body = @nvtableHTML,
			@body_format = 'HTML',
			@subject = 'Prod IFA Severity 2';
	END

END
