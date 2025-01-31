USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [stat].[uspKeyTypeXrefPullNewFromPrdBi02]

	Description: _DO_NOT_ run this sproc if you are not the custodian of the content in [PrdBi02].[Stat].[stat].[KeyTypeXref].
		You could end up pulling extra content not yet ready for prime time.

		This procedure inserts new KeyTypeXref rows from [PrdBi02].[Stat].[stat].[KeyTypeXref]
		into [IFA].[stat].[KeyTypeXref] on [PrdTrx01].

		This procedure _DOES_NOT_ push altered content of {existing} rows.  Only new rows.

		_Explicit_ [databasename].[schemaname].[tablename] has been used intentionally for 
		the local table ([IFA].[stat].[KeyTypeXref]).

		Parameter @pnvKeyTypeXrefId:
			If the value is NULL, the sproc will not pull any data.  
			If the value is "ALL", all new stats would be pulled.  
			If the value is a specific KeyTypeXrefId, the row for that KeyTypeXrefId will be pulled if it does not already exist in [PrdTrx01].[Stat].[stat].[KeyTypeXref].

	Tables: 
		 [PrdBi02].[Stat].[stat].[KeyTypeXref]
		,[IFA].[stat].[KeyTypeXref]

	History:
		2022-01-18 - LSW - Created.  Based on [stat].[uspKeyTypeXrefXrefPullNewFromPrdBi02].  (Could this have been built better?  Absolutely.)

*****************************************************************************************/
ALTER PROCEDURE [stat].[uspKeyTypeXrefPullNewFromPrdBi02](
	 @pnvCCF nvarchar(16) = NULL -- not used for any other purpose than to force the user to consider their actions carefully.
	,@ptiIsFeedbackOnly tinyint = 1 -- 1 = (default) provide feedback but do not commit any new data, 0 = commit any new data
	,@pnvKeyTypeXrefId nvarchar(5) = NULL -- if NULL, the sproc will not pull any data.  If "ALL", all new stat groups would be pulled.  If a specific KeyTypeXrefId is given, it will be pulled if it does not already exists in PrdTrx01.
)
AS
BEGIN -- [stat].[uspKeyTypeXrefPullNewFromPrdBi02]
	SET NOCOUNT ON;

	DECLARE @nvCCF nvarchar(16) = @pnvCCF
		,@nvCCFReversed nvarchar(16) = REVERSE( @pnvCCF )
		,@tiIsFeedbackOnly tinyint = @ptiIsFeedbackOnly
		,@nvFeedback nvarchar(max) = N'Feedback: new KeyTypeXref rows that would be added...' + NCHAR(013) + NCHAR(010)
		,@iSourceRecCount int = 0
		,@iInsertRecCount int = 0
		,@nvNewList nvarchar(max) = N'';

	IF @tiIsFeedbackOnly = 1
	BEGIN
		PRINT N'Feedback mode only.  New data will not be comitted.'
		PRINT N'Set parameter @ptiIsFeedbackOnly = 0 to enable comitting of any new data in [IFA].[stat].[KeyTypeXref].'
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
		PRINT N'_DO_NOT_ run this sproc if you are not the custodian of the content in [PrdBi02].[Stat].[stat].[KeyTypeXref].'
		PRINT N'Aborting sproc execution.'
		
		IF @tiIsFeedbackOnly = 0 
			RETURN (-1) -- if not feedback only mode, then the sproc stops here.
	END
	
	IF @pnvKeyTypeXrefId IS NULL OR ( @pnvKeyTypeXrefId IS NOT NULL AND @pnvKeyTypeXrefId <> N'ALL' AND ISNUMERIC( @pnvKeyTypeXrefId ) = 0 )
	BEGIN
		PRINT N'No @pnvKeyTypeXrefId value has been supplied.'
		PRINT N'_DO_NOT_ run this sproc if you are not the custodian of the content in [PrdBi02].[Stat].[stat].[KeyTypeXref].'
		PRINT N'@pnvKeyTypeXrefId must either be "ALL" or a valid KeyTypeXrefId that has not yet been migrated into [PrdTrx01].[IFA].[stat].[KeyTypeXref].'
		PRINT N'Aborting sproc execution.'
			
		IF @tiIsFeedbackOnly = 0 
			RETURN (-1) -- if not feedback only mode, then the sproc stops here.
	END
	
	DROP TABLE IF EXISTS #tblNewKeyTypeXref;

	SELECT
		 [KeyTypeXrefId]
		,[KeyTypeId]
		,[DescendantKeyTypeId]
		,DateActivated = SYSDATETIME() --We want to track when the metadata was inserted in PrdTrx01.
		,[KeyTypeProcessSeq]
	INTO #tblNewKeyTypeXref
	FROM [PrdBi02].[Stat].[stat].[KeyTypeXref] AS ktx
	WHERE ( @pnvKeyTypeXrefId = N'ALL' OR ( ISNUMERIC( @pnvKeyTypeXrefId ) = 1 AND ktx.[KeyTypeXrefId] = TRY_CONVERT( smallint, @pnvKeyTypeXrefId ) ) )
		AND ktx.[KeyTypeXrefId] > 0
		AND ktx.[KeyTypeId] > 0
		AND ktx.[DescendantKeyTypeId] > 0
		AND NOT EXISTS( SELECT 'X' FROM [IFA].[stat].[KeyTypeXref] AS x WHERE x.[KeyTypeXrefId] = ktx.[KeyTypeXrefId] )
		AND EXISTS( SELECT 'X' FROM [IFA].[stat].[KeyType] AS x WHERE x.[KeyTypeId] = ktx.[KeyTypeId] )
	ORDER BY ktx.[KeyTypeXrefId] ASC;

	SELECT @iSourceRecCount = COUNT(1) 
	FROM #tblNewKeyTypeXref;

	PRINT N'CCF Reference: ' + @nvCCF;
	PRINT N'';
	PRINT CONVERT( nvarchar(10), @iSourceRecCount ) + N' new KeyTypeXref rows found:';

	SELECT @nvNewList = @nvNewList
		+ NCHAR(013) + NCHAR(010)
		+ NCHAR(009) + ISNULL( TRY_CONVERT( nvarchar(max), [KeyTypeXrefId] ), N'{null}' ) 
		+ NCHAR(009) + ISNULL( TRY_CONVERT( nvarchar(max), [KeyTypeId] ), N'{null}' ) 
		+ NCHAR(009) + ISNULL( TRY_CONVERT( nvarchar(max), [DescendantKeyTypeId] ), N'{null}' ) 
		+ NCHAR(009) + N'{' + ISNULL( TRY_CONVERT( nvarchar(max), [DateActivated], 121 ), N'{null}' ) + N'}'
		+ NCHAR(009) + ISNULL( TRY_CONVERT( nvarchar(max), [KeyTypeProcessSeq] ), N'{null}' ) 
	FROM #tblNewKeyTypeXref
	ORDER BY KeyTypeXrefId ASC;

	PRINT @nvNewList;
	PRINT N'';

	IF @iSourceRecCount > 0
	BEGIN -- @iSourceRecCount > 0

		IF @tiIsFeedbackOnly = 0
		BEGIN
/* TO-DO: Enable the INSERT by disabling this comment block which is wrapped around said INSERT. */
			INSERT INTO [IFA].[stat].[KeyTypeXref](
				 [KeyTypeXrefId]
				,[KeyTypeId]
				,[DescendantKeyTypeId]
				,[DateActivated]
				,[KeyTypeProcessSeq]
			)
--*/
			SELECT 
				 [KeyTypeXrefId]
				,[KeyTypeId]
				,[DescendantKeyTypeId]
				,[DateActivated]
				,[KeyTypeProcessSeq]
			FROM #tblNewKeyTypeXref
			ORDER BY [KeyTypeXrefId] ASC;

			SET @iInsertRecCount = @@ROWCOUNT;
		
			IF @iInsertRecCount = @iSourceRecCount 
				PRINT N'All ' + CONVERT( nvarchar(10), @iInsertRecCount ) + N' new rows have been inserted into PrdTrx01.'; 
			ELSE 
				PRINT N'!!! Not all new rows were inserted into PrdTrx01 !!!';

		END
	
	END -- @iSourceRecCount > 0

	DROP TABLE IF EXISTS #tblNewKeyTypeXref;

END -- [stat].[uspKeyTypeXrefPullNewFromPrdBi02]
;
