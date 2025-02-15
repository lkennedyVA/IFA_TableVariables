USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [stat].[uspKeyTypePullNewFromPrdBi02]

	Description: _DO_NOT_ run this sproc if you are not the custodian of the content in [PrdBi02].[Stat].[stat].[KeyType].
		You could end up pulling extra content not yet ready for prime time.

		This procedure inserts new KeyType rows from [PrdBi02].[Stat].[stat].[KeyType]
		into [IFA].[stat].[KeyType] on [PrdTrx01].

		This procedure _DOES_NOT_ push altered content of {existing} rows.  Only new rows.

		_Explicit_ [databasename].[schemaname].[tablename] has been used intentionally for 
		the local table ([IFA].[stat].[KeyType]).

		Parameter @pnvKeyTypeId:
			If the value is NULL, the sproc will not pull any data.  
			If the value is "ALL", all new stats would be pulled.  
			If the value is a specific KeyTypeId, the row for that KeyTypeId will be pulled if it does not already exist in [PrdTrx01].[Stat].[stat].[KeyType].

	Tables: 
		 [PrdBi02].[Stat].[stat].[KeyType]
		,[IFA].[stat].[KeyType]

	History:
		2022-01-18 - LSW - Created.  Based on [stat].[uspKeyTypeXrefPullNewFromPrdBi02].  (Could this have been built better?  Absolutely.)

*****************************************************************************************/
ALTER PROCEDURE [stat].[uspKeyTypePullNewFromPrdBi02](
	 @pnvCCF nvarchar(16) = NULL -- not used for any other purpose than to force the user to consider their actions carefully.
	,@ptiIsFeedbackOnly tinyint = 1 -- 1 = (default) provide feedback but do not commit any new data, 0 = commit any new data
	,@pnvKeyTypeId nvarchar(5) = NULL -- if NULL, the sproc will not pull any data.  If "ALL", all new stat groups would be pulled.  If a specific KeyTypeId is given, it will be pulled if it does not already exists in PrdTrx01.
)
AS
BEGIN -- [stat].[uspKeyTypePullNewFromPrdBi02]
	SET NOCOUNT ON;

	DECLARE @nvCCF nvarchar(16) = @pnvCCF
		,@nvCCFReversed nvarchar(16) = REVERSE( @pnvCCF )
		,@tiIsFeedbackOnly tinyint = @ptiIsFeedbackOnly
		,@nvFeedback nvarchar(max) = N'Feedback: new KeyType rows that would be added...' + NCHAR(013) + NCHAR(010)
		,@iSourceRecCount int = 0
		,@iInsertRecCount int = 0
		,@nvNewList nvarchar(max) = N'';

	IF @tiIsFeedbackOnly = 1
	BEGIN
		PRINT N'Feedback mode only.  New data will not be comitted.'
		PRINT N'Set parameter @ptiIsFeedbackOnly = 0 to enable comitting of any new data in [IFA].[stat].[KeyType].'
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
		PRINT N'_DO_NOT_ run this sproc if you are not the custodian of the content in [PrdBi02].[Stat].[stat].[KeyType].'
		PRINT N'Aborting sproc execution.'
		
		IF @tiIsFeedbackOnly = 0 
			RETURN (-1) -- if not feedback only mode, then the sproc stops here.
	END
	
	IF @pnvKeyTypeId IS NULL OR ( @pnvKeyTypeId IS NOT NULL AND @pnvKeyTypeId <> N'ALL' AND ISNUMERIC( @pnvKeyTypeId ) = 0 )
	BEGIN
		PRINT N'No @pnvKeyTypeId value has been supplied.'
		PRINT N'_DO_NOT_ run this sproc if you are not the custodian of the content in [PrdBi02].[Stat].[stat].[KeyType].'
		PRINT N'@pnvKeyTypeId must either be "ALL" or a valid KeyTypeId that has not yet been migrated into [PrdTrx01].[IFA].[stat].[KeyType].'
		PRINT N'Aborting sproc execution.'
			
		IF @tiIsFeedbackOnly = 0 
			RETURN (-1) -- if not feedback only mode, then the sproc stops here.
	END
	
	DROP TABLE IF EXISTS #tblNewKeyType;

	SELECT
		 [KeyTypeId]
		,[KeyTypeCode]
		,[Name]
		,[Descr]
		,[KeyCount]
		,[KeyColumn]
		,[IsExternalKey]
		,[SourceDataTypeId]
		,[KeyTemplate]
		,[KeyTemplatePreprocessed]
		,DateActivated = SYSDATETIME() --We want to track when the metadata was inserted in PrdTrx01.
	INTO #tblNewKeyType
	FROM [PrdBi02].[Stat].[stat].[KeyType] AS kt
	WHERE ( @pnvKeyTypeId = N'ALL' OR ( ISNUMERIC( @pnvKeyTypeId ) = 1 AND kt.[KeyTypeId] = TRY_CONVERT( smallint, @pnvKeyTypeId ) ) )
		AND kt.[KeyTypeId] > 0
		AND kt.[KeyCount] > 0
		AND kt.[KeyColumn] IS NULL
		AND ( -- the 5 non-standard stat tables
					kt.[Name] NOT LIKE N'% ABA'
				AND kt.[Name] NOT LIKE N'% ABAAcct%'
				AND kt.[Name] NOT LIKE N'% OnUs Payer'
				AND kt.[Name] NOT LIKE N'% DS %'
				AND kt.[Name] NOT LIKE N'% DS'
			)
		AND NOT EXISTS( SELECT 'X' FROM [IFA].[stat].[KeyType] AS x WHERE x.[KeyTypeId] = kt.[KeyTypeId] )
	ORDER BY kt.[KeyTypeId] ASC;

	SELECT @iSourceRecCount = COUNT(1) 
	FROM #tblNewKeyType;

	PRINT N'CCF Reference: ' + @nvCCF;
	PRINT N'';
	PRINT CONVERT( nvarchar(10), @iSourceRecCount ) + N' new KeyType rows found:';

	SELECT @nvNewList = @nvNewList
		+ NCHAR(013) + NCHAR(010)
		+ NCHAR(009) + ISNULL( TRY_CONVERT( nvarchar(max), [KeyTypeId] ), N'{null}' ) 
		+ NCHAR(009) + ISNULL( [KeyTypeCode], N'{null}' ) 
		+ NCHAR(009) + N'"' + ISNULL( [Name], N'{null}' ) + N'"'
		+ NCHAR(009) + N'"' + ISNULL( [Descr], N'{null}' ) + N'"'
		+ NCHAR(009) + ISNULL( TRY_CONVERT( nvarchar(max), [KeyCount] ), N'{null}' )
		+ NCHAR(009) + N'"' + ISNULL( [KeyColumn], N'{null}' ) + N'"'
		+ NCHAR(009) + ISNULL( CASE WHEN [IsExternalKey] = 0 THEN N'0' WHEN [IsExternalKey] = 1 THEN N'1' ELSE NULL END , N'{null}' ) 
		+ NCHAR(009) + ISNULL( TRY_CONVERT( nvarchar(max), [SourceDataTypeId] ), N'{null}' ) 
		+ NCHAR(009) + N'{' + ISNULL( TRY_CONVERT( nvarchar(max), [DateActivated], 121 ), N'{null}' ) + N'}'
	FROM #tblNewKeyType
	ORDER BY KeyTypeId ASC;

	PRINT @nvNewList;
	PRINT N'';

	IF @iSourceRecCount > 0
	BEGIN -- @iSourceRecCount > 0

		IF @tiIsFeedbackOnly = 0
		BEGIN
/* TO-DO: Enable the INSERT by disabling this comment block which is wrapped around said INSERT. */
			INSERT INTO [IFA].[stat].[KeyType](
				 [KeyTypeId]
				,[KeyTypeCode]
				,[Name]
				,[Descr]
				,[KeyCount]
				,[KeyColumn]
				,[IsExternalKey]
				,[SourceDataTypeId]
				,[KeyTemplate]
				,[KeyTemplatePreprocessed]
				,[DateActivated]
			)
--*/
			SELECT 
				 [KeyTypeId]
				,[KeyTypeCode]
				,[Name]
				,[Descr]
				,[KeyCount]
				,[KeyColumn]
				,[IsExternalKey]
				,[SourceDataTypeId]
				,[KeyTemplate]
				,[KeyTemplatePreprocessed]
				,[DateActivated]
			FROM #tblNewKeyType
			ORDER BY [KeyTypeId] ASC;

			SET @iInsertRecCount = @@ROWCOUNT;
		
			IF @iInsertRecCount = @iSourceRecCount 
				PRINT N'All ' + CONVERT( nvarchar(10), @iInsertRecCount ) + N' new rows have been inserted into PrdTrx01.'; 
			ELSE 
				PRINT N'!!! Not all new rows were inserted into PrdTrx01 !!!';

		END
	
	END -- @iSourceRecCount > 0

	DROP TABLE IF EXISTS #tblNewKeyType;

END -- [stat].[uspKeyTypePullNewFromPrdBi02]
;
