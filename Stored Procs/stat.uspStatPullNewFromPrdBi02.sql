USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [stat].[uspStatPullNewFromPrdBi02]

	Description: _DO_NOT_ run this sproc if you are not the custodian of the content in [PrdBi02].[Stat].[stat].[Stat].
		You could end up pulling extra content not yet ready for prime time.

		This procedure inserts new Stat rows from [PrdBi02].[Stat].[stat].[Stat]
		into [IFA].[stat].[Stat] on [PrdTrx01].

		This procedure _DOES_NOT_ push altered content of {existing} rows.  Only new rows.

		_Explicit_ [databasename].[schemaname].[tablename] has been used intentionally for 
		the local table ([IFA].[stat].[Stat]).

	Tables: [PrdBi02].[Stat].[stat].[Stat]
		,[IFA].[stat].[Stat]

	History:
		2021-01-05 - LWhiting - Created.  (Could this have been built better?  Absolutely.)
		2021-02-25 - LWhiting - Added parameter @ptiIsFeedbackOnly during CCF2430.  Also reduced number of Linked Server queries down to one.
		2021-03-01 - LWhiting - Added parameter @pnvStatId after a discussion with Chris.
										If the value is NULL, the sproc will not pull any data.  
										If the value is "ALL", all new stats would be pulled.  
										If the value is a specific StatId, the row for that StatId will be pulled if it does not already exist in [PrdTrx01].[IFA].[stat].[Stat].
		2021-03-01 - CBS - Updated references from [PrdBi02].[Stat].[stat].[uspStat_PullNewFromPrdBi03] to use Bi02.Stat as the source and PrdTrx01.IFA as the destination
*****************************************************************************************/
ALTER PROCEDURE [stat].[uspStatPullNewFromPrdBi02](
	 @pnvCCF nvarchar(16) = NULL -- not used for any other purpose than to force the user to consider their actions carefully.
	,@ptiIsFeedbackOnly tinyint = 1 -- 1 = (default) provide feedback but do not commit any new data, 0 = commit any new data
	,@pnvStatId nvarchar(5) = NULL -- if NULL, the sproc will not pull any data.  If "ALL", all new stats would be pulled.  If a specific StatId is given, it will be pulled if it does not already exists in PrdBi02.
)
AS
BEGIN -- [stat].[uspStatPullNewFromPrdBi02]
	SET NOCOUNT ON;
	DECLARE @tbNewStatList table ( StatId smallint not null );
	DECLARE @nvCCF nvarchar(16) = @pnvCCF
		,@nvCCFReversed nvarchar(16) = REVERSE( @pnvCCF )
		,@tiIsFeedbackOnly tinyint = @ptiIsFeedbackOnly
		,@nvFeedback nvarchar(max) = N'Feedback: new Stat rows that would be added...' + NCHAR(013) + NCHAR(010)
		,@iSourceRecCount int = 0
		,@iInsertRecCount int = 0
		,@nvNewStatList nvarchar(max) = N'';
	
	IF @tiIsFeedbackOnly = 1
	BEGIN
		PRINT N'Feedback mode only.  New data will not be comitted.'
		PRINT N'Set parameter @ptiIsFeedbackOnly = 0 to enable comitting of any new data in [IFA].[stat].[Stat].'
	END
	ELSE
	BEGIN
		PRINT N'Not in feedback only mode.'
		PRINT N'New data will be comitted.'
	END

	PRINT N'';

	IF @nvCCF IS NULL -- if no CCF was supplied
			OR ( -- or if the last 4 characters of the string are not numeric characters (btw: there is a flaw in this; "." and "-" are considered numeric
				ISNUMERIC( SUBSTRING( @nvCCFReversed, 1, 1 ) ) = 0 
					OR ISNUMERIC( SUBSTRING( @nvCCFReversed, 2, 1 ) ) = 0 
					OR ISNUMERIC( SUBSTRING( @nvCCFReversed, 3, 1 ) ) = 0 
					OR ISNUMERIC( SUBSTRING( @nvCCFReversed, 4, 1 ) ) = 0 
				)
	BEGIN
		PRINT N'No @pnvCCF value has been supplied.'
		PRINT N'_DO_NOT_ run this sproc if you are not the custodian of the content in [PrdBi02].[Stat].[stat].[Stat].'
		PRINT N'Aborting sproc execution.'
		
		IF @tiIsFeedbackOnly = 0 
			RETURN (-1) -- if not feedback only mode, then the sproc stops here.
	END
	
	IF @pnvStatId IS NULL OR ( @pnvStatId IS NOT NULL AND @pnvStatId <> N'ALL' AND ISNUMERIC( @pnvStatId ) = 0 )
	BEGIN
		PRINT N'No @pnvStatId value has been supplied.'
		PRINT N'_DO_NOT_ run this sproc if you are not the custodian of the content in [PrdBi02].[Stat].[stat].[Stat].'
		PRINT N'@pnvStatId must either be "ALL" or a valid StatId that has not yet been migrated into [PrdTrx01].[IFA].[stat].[Stat].'
		PRINT N'Aborting sproc execution.'
		
		IF @tiIsFeedbackOnly = 0 
			RETURN (-1) -- if not feedback only mode, then the sproc stops here.
	END

	DROP TABLE IF EXISTS #tblNewStat;

	SELECT StatId
		,StatCode
		,[Name]
		,IsOLTP
		,TargetTable
		,DataType
		,DefaultValue
		,HadoopStatNameId
		,HadoopReference
		,HadoopComment
		,StatusFlag
		,SYSDATETIME() AS [DateActivated] --We want to track when the metadata was inserted in PrdTrx01.
	INTO #tblNewStat
	FROM [PrdBi02].[Stat].[stat].[Stat] AS s 
	WHERE ( @pnvStatId = N'ALL' OR ( ISNUMERIC( @pnvStatId ) = 1 AND s.StatId = TRY_CONVERT( smallint, @pnvStatId ) ) )
		AND NOT EXISTS( SELECT 'X' FROM [IFA].[stat].[Stat] AS x WHERE x.StatId = s.[StatId] )
	ORDER BY [StatId] ASC;

	INSERT INTO @tbNewStatList ( [StatId] )
	SELECT [StatId] 
	FROM #tblNewStat;

	SELECT @iSourceRecCount = COUNT(1) 
	FROM @tbNewStatList;

	PRINT N'CCF Reference: ' + @nvCCF;
	PRINT N'';
	PRINT CONVERT( nvarchar(10), @iSourceRecCount ) + N' new Stats found:';

	SELECT @nvNewStatList = @nvNewStatList
		+ NCHAR(013) + NCHAR(010)
		+ NCHAR(009) + ISNULL( TRY_CONVERT( nvarchar(max), [StatId] ), N'{null}' ) 
		+ NCHAR(009) + N'"' + ISNULL( TRY_CONVERT( nvarchar(max), [Name] ), N'{null}' ) + N'"'
		+ NCHAR(009) + N'{' + ISNULL( TRY_CONVERT( nvarchar(max), [StatCode] ), N'{null}' ) + N'}'
		--'feedback' AS [new Stat would be added],
		-- [StatId]
		--,[StatCode]
		--,[Name]
		--,[IsOLTP]
		--,[TargetTable]
		--,[DataType]
		--,[DefaultValue]
		--,[HadoopStatNameId]
		--,[HadoopReference]
		--,[HadoopComment]
		--,[StatusFlag]
		--,[DateActivated]
	FROM #tblNewStat
	ORDER BY StatId ASC;

	PRINT @nvNewStatList;
	PRINT N'';


	IF @iSourceRecCount > 0
	BEGIN -- @iSourceRecCount > 0

		IF @tiIsFeedbackOnly = 0
		BEGIN
			INSERT INTO [IFA].[stat].[Stat](
				 [StatId]
				,[StatCode]
				,[Name]
				,[TargetTable]
				,[DataType]
				,[DefaultValue]
				,[HadoopReference]
				,[StatusFlag]
				,[DateActivated]
			)
			SELECT StatId
				,StatCode
				,[Name]
				,TargetTable
				,DataType
				,DefaultValue
				,HadoopReference
				,StatusFlag
				,DateActivated
			FROM #tblNewStat
			ORDER BY [StatId] ASC;

			SET @iInsertRecCount = @@ROWCOUNT;
	
			IF @iInsertRecCount = @iSourceRecCount 
				PRINT N'All ' + CONVERT( nvarchar(10), @iInsertRecCount ) + N' new rows have been inserted into PrdTrx01.'; 
			ELSE 
				PRINT N'!!! Not all new rows were inserted into PrdTrx01 !!!';
		END
	END -- @iSourceRecCount > 0

	DROP TABLE IF EXISTS #tblNewStat;

END -- [stat].[uspStatPullNewFromPrdBi02]
;
