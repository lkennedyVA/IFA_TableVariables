USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [stat].[uspStatGroupFilterXrefPullNewFromPrdBi02]

	Description: _DO_NOT_ run this sproc if you are not the custodian of the content in [PrdBi03].[Stat].[stat].[StatGroupFilterXref].
		You could end up pulling extra content not yet ready for prime time.

		This procedure inserts new StatGroupFilterXref rows from [PrdBi02].[Stat].[stat].[StatGroupFilterXref]
		into [IFA].[stat].[StatGroupFilterXref] on [PrdTrx01].

		This procedure _DOES_NOT_ push altered content of {existing} rows.  Only new rows.

		_Explicit_ [databasename].[schemaname].[tablename] has been used intentionally for 
		the local table ([IFA].[stat].[StatGroupFilterXref]).

		Parameter @pnvStatGroupFilterXrefId:
			If the value is NULL, the sproc will not pull any data.  
			If the value is "ALL", all new stats would be pulled.  
			If the value is a specific StatGroupFilterXrefId, the row for that StatGroupFilterXrefId will be pulled if it does not already exist in [PrdTrx01].[IFA].[stat].[StatGroupFilterXref].

	Tables: 
		 [PrdBi02].[Stat].[stat].[StatGroupFilterXref]
		,[IFA].[stat].[StatGroupFilterXref]

	History:
		2024-04-04 - LSW - VALID-1755: Created.  Based on [stat].[uspStatGroupKeyTypeXref_PullNewFromPrdBi02].

*****************************************************************************************/
ALTER PROCEDURE [stat].[uspStatGroupFilterXrefPullNewFromPrdBi02](
	 @pnvCCF nvarchar(16) = NULL -- not used for any other purpose than to force the user to consider their actions carefully.
	,@ptiIsFeedbackOnly tinyint = 1 -- 1 = (default) provide feedback but do not commit any new data, 0 = commit any new data
	,@pnvStatGroupFilterXrefId nvarchar(5) = NULL -- if NULL, the sproc will not pull any data.  If "ALL", all new stat groups would be pulled.  If a specific StatGroupFilterXrefId is given, it will be pulled if it does not already exists in PrdBi02.
)
AS
BEGIN -- [stat].[uspStatGroupFilterXrefPullNewFromPrdBi02]
	SET NOCOUNT ON;

	DECLARE @nvCCF nvarchar(16) = @pnvCCF
		,@nvCCFReversed nvarchar(16) = REVERSE( @pnvCCF )
		,@tiIsFeedbackOnly tinyint = @ptiIsFeedbackOnly
		,@nvFeedback nvarchar(max) = N'Feedback: new StatGroupFilterXref rows that would be added...' + NCHAR(013) + NCHAR(010)
		,@iSourceRecCount int = 0
		,@iInsertRecCount int = 0
		,@nvNewList nvarchar(max) = N'';

	IF @tiIsFeedbackOnly = 1
	BEGIN
		PRINT N'Feedback mode only.  New data will not be comitted.'
		PRINT N'Set parameter @ptiIsFeedbackOnly = 0 to enable comitting of any new data in [Stat].[stat].[StatGroupFilterXref].'
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
		PRINT N'_DO_NOT_ run this sproc if you are not the custodian of the content in [PrdBi03].[Stat].[stat].[StatGroupFilterXref].'
		PRINT N'Aborting sproc execution.'
		
		IF @tiIsFeedbackOnly = 0 
			RETURN (-1) -- if not feedback only mode, then the sproc stops here.
	END
	
	IF @pnvStatGroupFilterXrefId IS NULL OR ( @pnvStatGroupFilterXrefId IS NOT NULL AND @pnvStatGroupFilterXrefId <> N'ALL' AND ISNUMERIC( @pnvStatGroupFilterXrefId ) = 0 )
	BEGIN
		PRINT N'No @pnvStatGroupFilterXrefId value has been supplied.'
		PRINT N'_DO_NOT_ run this sproc if you are not the custodian of the content in [PrdBi03].[Stat].[stat].[StatGroupFilterXref].'
		PRINT N'@pnvStatGroupFilterXrefId must either be "ALL" or a valid StatGroupFilterXrefId that has not yet been migrated into [PrdBi02].[Stat].[stat].[StatGroupFilterXref].'
		PRINT N'Aborting sproc execution.'
			
		IF @tiIsFeedbackOnly = 0 
			RETURN (-1) -- if not feedback only mode, then the sproc stops here.
	END
	
	DROP TABLE IF EXISTS #tblNewStatGroupFilterXref;

	SELECT
		 [StatGroupFilterXrefId]
		,[StatGroupId]
		,[FilterId]
		,DateActivated = SYSDATETIME() --We want to track when the metadata was inserted in PrdTrx01.
	INTO #tblNewStatGroupFilterXref
	FROM [PrdBi02].[Stat].[stat].[StatGroupFilterXref] AS sgfx
	WHERE ( @pnvStatGroupFilterXrefId = N'ALL' OR ( ISNUMERIC( @pnvStatGroupFilterXrefId ) = 1 AND sgfx.[StatGroupFilterXrefId] = TRY_CONVERT( smallint, @pnvStatGroupFilterXrefId ) ) )
		AND sgfx.[StatGroupFilterXrefId] > 0
		AND sgfx.[StatGroupId] > 0
		AND sgfx.[FilterId] > 0
		AND NOT EXISTS( SELECT 'X' FROM [IFA].[stat].[StatGroupFilterXref] AS x WHERE x.[StatGroupFilterXrefId] = sgfx.[StatGroupFilterXrefId] )
	ORDER BY sgfx.[StatGroupFilterXrefId] ASC;

	SELECT @iSourceRecCount = COUNT(1) 
	FROM #tblNewStatGroupFilterXref;

	PRINT N'CCF Reference: ' + ISNULL( TRY_CONVERT( nvarchar(max), @nvCCF ), N'{@nvCFF:null}' );
	PRINT N'';
	PRINT CONVERT( nvarchar(10), @iSourceRecCount ) + N' new StatGroupFilterXref rows found:';

	SELECT @nvNewList = @nvNewList
		+ NCHAR(013) + NCHAR(010)
		+ NCHAR(009) + ISNULL( TRY_CONVERT( nvarchar(max), [StatGroupFilterXrefId] ), N'{null}' ) 
		+ NCHAR(009) + ISNULL( TRY_CONVERT( nvarchar(max), [StatGroupId] ), N'{null}' ) 
		+ NCHAR(009) + ISNULL( TRY_CONVERT( nvarchar(max), [FilterId] ), N'{null}' ) 
		+ NCHAR(009) + N'{' + ISNULL( TRY_CONVERT( nvarchar(max), [DateActivated], 121 ), N'{null}' ) + N'}'
	FROM #tblNewStatGroupFilterXref
	ORDER BY StatGroupFilterXrefId ASC;

	SET @nvNewList = @nvNewList + NCHAR(013) + NCHAR(010)
	;

	SELECT @nvNewList = @nvNewList
		+ NCHAR(013) + NCHAR(010)
		+ N'exec [stat].[uspStatGroupFilterXrefPullNewFromPrdBi02]
	 @pnvCCF = N''' + ISNULL( TRY_CONVERT( nvarchar(max), @nvCCF ), N'{@nvCCF:null}' ) + N''' -- not used for any other purpose than to force the user to consider their actions carefully.
	,@ptiIsFeedbackOnly = 1 -- 1 = (default) provide feedback but do not commit any new data, 0 = commit any new data
	,@pnvStatGroupFilterXrefId = N''' + ISNULL( TRY_CONVERT( nvarchar(max), [StatGroupFilterXrefId] ), N'{StatGroupFilterXrefId:null}' ) + N'''
;
'
	FROM #tblNewStatGroupFilterXref
	ORDER BY StatGroupFilterXrefId ASC;

	--PRINT @nvNewList;
	EXEC [DBA].[dbo].[uspPrintFullString] @nvNewList
	PRINT N'';

	IF @iSourceRecCount > 0
	BEGIN -- @iSourceRecCount > 0

		IF @tiIsFeedbackOnly = 0
		BEGIN
/* TO-DO: Enable the INSERT by disabling this comment block which is wrapped around said INSERT. */
			INSERT INTO [IFA].[stat].[StatGroupFilterXref](
				 [StatGroupFilterXrefId]
				,[StatGroupId]
				,[FilterId]
				,[DateActivated]
			)
--*/
			SELECT 
				 [StatGroupFilterXrefId]
				,[StatGroupId]
				,[FilterId]
				,[DateActivated]
			FROM #tblNewStatGroupFilterXref
			ORDER BY [StatGroupFilterXrefId] ASC;

			SET @iInsertRecCount = @@ROWCOUNT
			;
		
			IF @iInsertRecCount = @iSourceRecCount 
				PRINT N'All ' + CONVERT( nvarchar(10), @iInsertRecCount ) + N' new rows have been inserted into PrdTrx01.IFA.'; 
			ELSE 
				PRINT N'!!! WARNING: Not all new rows were inserted into PrdTrx01.IFA !!!';

		END
	
	END -- @iSourceRecCount > 0

	DROP TABLE IF EXISTS #tblNewStatGroupFilterXref;

END -- [stat].[uspStatGroupFilterXrefPullNewFromPrdBi02]
;
