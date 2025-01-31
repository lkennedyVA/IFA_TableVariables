USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [stat].[uspStatGroupKeyTypeXrefPullNewFromPrdBi02]

	Description: _DO_NOT_ run this sproc if you are not the custodian of the content in [PrdBi02].[Stat].[stat].[StatGroupKeyTypeXref].
		You could end up pulling extra content not yet ready for prime time.

		This procedure inserts new StatGroupKeyTypeXref rows from [PrdBi02].[Stat].[stat].[StatGroupKeyTypeXref]
		into [IFA].[stat].[StatGroupKeyTypeXref] on [PrdTrx01].

		This procedure _DOES_NOT_ push altered content of {existing} rows.  Only new rows.

		_Explicit_ [databasename].[schemaname].[tablename] has been used intentionally for 
		the local table ([IFA].[stat].[StatGroupKeyTypeXref]).

		Parameter @pnvStatGroupKeyTypeXrefId:
			If the value is NULL, the sproc will not pull any data.  
			If the value is "ALL", all new stats would be pulled.  
			If the value is a specific StatGroupKeyTypeXrefId, the row for that StatGroupKeyTypeXrefId will be pulled if it does not already exist in [PrdTrx01].[Stat].[stat].[StatGroupKeyTypeXref].

	Tables: 
		 [PrdBi02].[Stat].[stat].[StatGroupKeyTypeXref]
		,[IFA].[stat].[StatGroupKeyTypeXref]

	History:
		2022-01-18 - LSW - Created.  Based on [stat].[uspStatGroupKeyTypeXrefXrefPullNewFromPrdBi02].  (Could this have been built better?  Absolutely.)

*****************************************************************************************/
ALTER PROCEDURE [stat].[uspStatGroupKeyTypeXrefPullNewFromPrdBi02](
	 @pnvCCF nvarchar(16) = NULL -- not used for any other purpose than to force the user to consider their actions carefully.
	,@ptiIsFeedbackOnly tinyint = 1 -- 1 = (default) provide feedback but do not commit any new data, 0 = commit any new data
	,@pnvStatGroupKeyTypeXrefId nvarchar(5) = NULL -- if NULL, the sproc will not pull any data.  If "ALL", all new stat groups would be pulled.  If a specific StatGroupKeyTypeXrefId is given, it will be pulled if it does not already exists in PrdTrx01.
)
AS
BEGIN -- [stat].[uspStatGroupKeyTypeXrefPullNewFromPrdBi02]
	SET NOCOUNT ON;

	DECLARE @nvCCF nvarchar(16) = @pnvCCF
		,@nvCCFReversed nvarchar(16) = REVERSE( @pnvCCF )
		,@tiIsFeedbackOnly tinyint = @ptiIsFeedbackOnly
		,@nvFeedback nvarchar(max) = N'Feedback: new StatGroupKeyTypeXref rows that would be added...' + NCHAR(013) + NCHAR(010)
		,@iSourceRecCount int = 0
		,@iInsertRecCount int = 0
		,@nvNewList nvarchar(max) = N'';

	IF @tiIsFeedbackOnly = 1
	BEGIN
		PRINT N'Feedback mode only.  New data will not be comitted.'
		PRINT N'Set parameter @ptiIsFeedbackOnly = 0 to enable comitting of any new data in [IFA].[stat].[StatGroupKeyTypeXref].'
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
		PRINT N'_DO_NOT_ run this sproc if you are not the custodian of the content in [PrdBi02].[Stat].[stat].[StatGroupKeyTypeXref].'
		PRINT N'Aborting sproc execution.'
		
		IF @tiIsFeedbackOnly = 0 
			RETURN (-1) -- if not feedback only mode, then the sproc stops here.
	END
	
	IF @pnvStatGroupKeyTypeXrefId IS NULL OR ( @pnvStatGroupKeyTypeXrefId IS NOT NULL AND @pnvStatGroupKeyTypeXrefId <> N'ALL' AND ISNUMERIC( @pnvStatGroupKeyTypeXrefId ) = 0 )
	BEGIN
		PRINT N'No @pnvStatGroupKeyTypeXrefId value has been supplied.'
		PRINT N'_DO_NOT_ run this sproc if you are not the custodian of the content in [PrdBi02].[Stat].[stat].[StatGroupKeyTypeXref].'
		PRINT N'@pnvStatGroupKeyTypeXrefId must either be "ALL" or a valid StatGroupKeyTypeXrefId that has not yet been migrated into [PrdTrx01].[IFA].[stat].[StatGroupKeyTypeXref].'
		PRINT N'Aborting sproc execution.'
			
		IF @tiIsFeedbackOnly = 0 
			RETURN (-1) -- if not feedback only mode, then the sproc stops here.
	END
	
	DROP TABLE IF EXISTS #tblNewStatGroupKeyTypeXref;

	SELECT
		 [StatGroupKeyTypeXrefId]
		,[StatGroupId]
		,[KeyTypeId]
		,DateActivated = SYSDATETIME() --We want to track when the metadata was inserted in PrdTrx01.
	INTO #tblNewStatGroupKeyTypeXref
	FROM [PrdBi02].[Stat].[stat].[StatGroupKeyTypeXref] AS sg
	WHERE ( @pnvStatGroupKeyTypeXrefId = N'ALL' OR ( ISNUMERIC( @pnvStatGroupKeyTypeXrefId ) = 1 AND sg.[StatGroupKeyTypeXrefId] = TRY_CONVERT( smallint, @pnvStatGroupKeyTypeXrefId ) ) )
		AND sg.[StatGroupKeyTypeXrefId] > 0
		AND sg.[StatGroupId] > 0
		AND sg.[KeyTypeId] > 0
		AND NOT EXISTS( SELECT 'X' FROM [IFA].[stat].[StatGroupKeyTypeXref] AS x WHERE x.[StatGroupKeyTypeXrefId] = sg.[StatGroupKeyTypeXrefId] )
	ORDER BY sg.[StatGroupKeyTypeXrefId] ASC;

	SELECT @iSourceRecCount = COUNT(1) 
	FROM #tblNewStatGroupKeyTypeXref;

	PRINT N'CCF Reference: ' + @nvCCF;
	PRINT N'';
	PRINT CONVERT( nvarchar(10), @iSourceRecCount ) + N' new StatGroupKeyTypeXref rows found:';

	SELECT @nvNewList = @nvNewList
		+ NCHAR(013) + NCHAR(010)
		+ NCHAR(009) + ISNULL( TRY_CONVERT( nvarchar(max), [StatGroupKeyTypeXrefId] ), N'{null}' ) 
		+ NCHAR(009) + ISNULL( TRY_CONVERT( nvarchar(max), [StatGroupId] ), N'{null}' ) 
		+ NCHAR(009) + ISNULL( TRY_CONVERT( nvarchar(max), [KeyTypeId] ), N'{null}' ) 
		+ NCHAR(009) + N'{' + ISNULL( TRY_CONVERT( nvarchar(max), [DateActivated], 121 ), N'{null}' ) + N'}'
	FROM #tblNewStatGroupKeyTypeXref
	ORDER BY StatGroupKeyTypeXrefId ASC;

	PRINT @nvNewList;
	PRINT N'';

	IF @iSourceRecCount > 0
	BEGIN -- @iSourceRecCount > 0

		IF @tiIsFeedbackOnly = 0
		BEGIN
/* TO-DO: Enable the INSERT by disabling this comment block which is wrapped around said INSERT. */
			INSERT INTO [IFA].[stat].[StatGroupKeyTypeXref](
				 [StatGroupKeyTypeXrefId]
				,[StatGroupId]
				,[KeyTypeId]
				,[DateActivated]
			)
--*/
			SELECT 
				 [StatGroupKeyTypeXrefId]
				,[StatGroupId]
				,[KeyTypeId]
				,[DateActivated]
			FROM #tblNewStatGroupKeyTypeXref
			ORDER BY [StatGroupKeyTypeXrefId] ASC;

			SET @iInsertRecCount = @@ROWCOUNT;
		
			IF @iInsertRecCount = @iSourceRecCount 
				PRINT N'All ' + CONVERT( nvarchar(10), @iInsertRecCount ) + N' new rows have been inserted into PrdTrx01.'; 
			ELSE 
				PRINT N'!!! Not all new rows were inserted into PrdTrx01 !!!';

		END
	
	END -- @iSourceRecCount > 0

	DROP TABLE IF EXISTS #tblNewStatGroupKeyTypeXref;

END -- [stat].[uspStatGroupKeyTypeXrefPullNewFromPrdBi02]
;
