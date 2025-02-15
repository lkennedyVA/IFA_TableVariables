USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*******************************************************************
	Name:	[stat].[uspCheckNumberSequenceBuild]
	Created By: Chris Sharp
	Date: 2016-11-04
	Description: Procedure to repopulate [stat].[CheckNumberSequence] for 
		Rules 455 and 456. Should be run early morning before transactions are processed.
 	 
	Tables:	[ifa].[Item]
		,[stat].[CheckNumberSequence]

	Procedures: [common].[uspTruncateTable]
 
	History:
		2016-06-28 - LBD - Created, used uspPayerCheckSequenceBuild	
		2018-09-26 - LBD - Modified, adjusted to use try_convert on checknumber
		2025-01-15 - LXK - Replaced table variables with local temp tables
*******************************************************************/
ALTER   PROCEDURE [stat].[uspCheckNumberSequenceBuild]
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #CheckNumberSequence
	create table #CheckNumberSequence(
		 PayerId bigint primary key
		,MinCheckNumberAllowed bigint
		,MaxCheckNumberAllowed bigint
		,DBProcessCode nvarchar(25)
	);
	drop table if exists #CheckNumberSequenceLArgeOrSmall
	create table #CheckNumberSequenceLArgeOrSmall(
		 PayerId bigint primary key
		,PayerCount int
		,RoutingNumber nchar(9)
		,AccountNumber nvarchar(50)	
	);
																																																																										
	DECLARE @dtStartDate date
		,@dtEndDate date
		,@iProcessedItemStatusId int = [common].[ufnItemStatus]('Processed')
		,@iFinalItemStatusId int = [common].[ufnItemStatus]('Final')
		,@iErrorDetailId INT
		,@sSchemaName nvarchar(128);

	SET @sSchemaName = N'stat';

	EXECUTE [stat].[uspTruncateTable] @pnvTargetTable = '[stat].[CheckNumberSequence]'

	BEGIN TRY
		--Load @PayerCount
		INSERT INTO #CheckNumberSequenceLArgeOrSmall(PayerId,PayerCount,RoutingNumber,AccountNumber)
		SELECT i.PayerId, COUNT(i.ItemId),p.RoutingNumber,p.AccountNumber 
		FROM [ifa].[Item] i WITH (NOLOCK)
		INNER JOIN [payer].[Payer] p (NOLOCK) ON i.PayerId = p.PayerId
		WHERE ISNULL(TRY_CONVERT(bigint,i.CheckNumber),0) <> 0
			AND i.ItemStatusId in (@iProcessedItemStatusId,@iFinalItemStatusId)
			AND i.RuleBreak = N'0'
			AND p.RoutingNumber <> N'000000518'
		GROUP BY i.PayerId,p.RoutingNumber,p.AccountNumber;

		--DBProcess Rule456
		SET @dtStartDate = DATEADD(DAY,-45,SYSDATETIME());	
		SET @dtEndDate  = DATEADD(DAY,-15,SYSDATETIME());
		INSERT INTO #CheckNumberSequence(PayerId, MinCheckNumberAllowed, MaxCheckNumberAllowed, DBProcessCode)
		SELECT los.PayerId
			,(MIN(TRY_CONVERT(bigint,i.CheckNumber)) - 1000) as MinCheckNumberAllowed
			,CASE WHEN ((MAX(TRY_CONVERT(bigint,i.CheckNumber)) - MIN(TRY_CONVERT(bigint,i.CheckNumber)))*2) > 1000 
					THEN (((MAX(TRY_CONVERT(bigint,i.CheckNumber)) - MIN(TRY_CONVERT(bigint,i.CheckNumber))) * 2) + MAX(TRY_CONVERT(bigint,i.CheckNumber)))
					ELSE (MAX((TRY_CONVERT(bigint,i.CheckNumber))) + 1000) END AS MaxAllowedCheckNumber
			,'Rule456'
		FROM #CheckNumberSequenceLArgeOrSmall los
		INNER JOIN [ifa].[Item] i ON los.PayerId = i.PayerId
		WHERE ISNULL(TRY_CONVERT(bigint,i.CheckNumber),0) <> 0
			AND i.ItemStatusId = @iFinalItemStatusId
			AND i.RuleBreak = N'0'
			AND i.DateActivated BETWEEN @dtStartDate AND @dtEndDate
			AND los.PayerCount > 50		
		GROUP BY los.PayerId
		HAVING COUNT(i.ItemId) > 6;

		--DBProcess Rule455
		SET @dtStartDate = DATEADD(DAY,-365,SYSDATETIME());	
		SET @dtEndDate  = DATEADD(DAY,-1,SYSDATETIME());
		INSERT INTO #CheckNumberSequence(PayerId, MinCheckNumberAllowed, MaxCheckNumberAllowed, DBProcessCode)																																		
		SELECT i.PayerId																																																																								
			,MIN(TRY_CONVERT(bigint,i.CheckNumber)) AS MinCheckNumberAllowed 		
			,CASE WHEN ((MAX(TRY_CONVERT(bigint,i.CheckNumber)) - MIN(TRY_CONVERT(bigint,i.CheckNumber))) < 10000) THEN (MAX(TRY_CONVERT(bigint,i.CheckNumber)) + 2000)																																			
				WHEN ((MAX(TRY_CONVERT(bigint,i.CheckNumber)) - MIN(TRY_CONVERT(bigint,i.CheckNumber))) >= 10000 AND (MAX(TRY_CONVERT(bigint,i.CheckNumber)) - MIN(TRY_CONVERT(bigint,i.CheckNumber)) <= 100000)) THEN (MAX(TRY_CONVERT(bigint,i.CheckNumber)) + 5000)
				WHEN ((MAX(TRY_CONVERT(bigint,i.CheckNumber)) - MIN(TRY_CONVERT(bigint,i.CheckNumber))) > 100000) THEN (MAX(TRY_CONVERT(bigint,i.CheckNumber)) + 10000) END AS MaxCheckNumberAllowed			
			,'Rule455'
		FROM [ifa].[Item] i	
		INNER JOIN #CheckNumberSequenceLArgeOrSmall los on i.PayerId = los.PayerId
		WHERE NOT EXISTS (SELECT 'X' FROM #CheckNumberSequence cns WHERE i.PayerId = cns.PayerId)	
			AND i.ItemStatusId in (@iProcessedItemStatusId,@iFinalItemStatusId)
			AND i.RuleBreak = N'0'
			AND i.DateActivated BETWEEN @dtStartDate AND @dtEndDate
			AND los.PayerCount <= 50																																																																								
		GROUP BY i.PayerId
		HAVING COUNT(i.ItemId) >= 2;																																						

		INSERT INTO [stat].[CheckNumberSequence](PayerId, MinCheckNumberAllowed, MaxCheckNumberAllowed, DBProcessCode)
		SELECT PayerId, MinCheckNumberAllowed, MaxCheckNumberAllowed, DBProcessCode
		FROM #CheckNumberSequence;
	END TRY
	BEGIN CATCH
        EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
	END CATCH
END

