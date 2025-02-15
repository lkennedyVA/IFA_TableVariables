USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [stat].[uspStatGroupPullNewFromPrdBi02]

	Description: _DO_NOT_ run this sproc if you are not the custodian of the content in [PrdBi02].[Stat].[stat].[StatGroup].
		You could end up pulling extra content not yet ready for prime time.

		This procedure inserts new StatGroup rows from [PrdBi02].[Stat].[stat].[StatGroup]
		into [IFA].[stat].[StatGroup] on [PrdTrx01].

		This procedure _DOES_NOT_ push altered content of {existing} rows.  Only new rows.

		_Explicit_ [databasename].[schemaname].[tablename] has been used intentionally for 
		the local table ([IFA].[stat].[StatGroup]).

		Parameter @pnvStatGroupId:
			If the value is NULL, the sproc will not pull any data.  
			If the value is "ALL", all new stats would be pulled.  
			If the value is a specific StatGroupId, the row for that StatGroupId will be pulled if it does not already exist in [PrdTrx01].[Stat].[stat].[StatGroup].

	Tables: 
		 [PrdBi02].[Stat].[stat].[StatGroup]
		,[IFA].[stat].[StatGroup]

	History:
		2022-01-18 - LSW - Created.  Based on [stat].[uspStatGroupXrefPullNewFromPrdBi02].  (Could this have been built better?  Absolutely.)

*****************************************************************************************/
ALTER PROCEDURE [stat].[uspStatGroupPullNewFromPrdBi02](
	 @pnvCCF nvarchar(16) = NULL -- not used for any other purpose than to force the user to consider their actions carefully.
	,@ptiIsFeedbackOnly tinyint = 1 -- 1 = (default) provide feedback but do not commit any new data, 0 = commit any new data
	,@pnvStatGroupId nvarchar(5) = NULL -- if NULL, the sproc will not pull any data.  If "ALL", all new stat groups would be pulled.  If a specific StatGroupId is given, it will be pulled if it does not already exists in PrdTrx01.
)
AS
BEGIN -- [stat].[uspStatGroupPullNewFromPrdBi02]
	SET NOCOUNT ON;

	DECLARE @nvCCF nvarchar(16) = @pnvCCF
		,@nvCCFReversed nvarchar(16) = REVERSE( @pnvCCF )
		,@tiIsFeedbackOnly tinyint = @ptiIsFeedbackOnly
		,@nvFeedback nvarchar(max) = N'Feedback: new StatGroup rows that would be added...' + NCHAR(013) + NCHAR(010)
		,@iSourceRecCount int = 0
		,@iInsertRecCount int = 0
		,@nvNewStatList nvarchar(max) = N'';

	IF @tiIsFeedbackOnly = 1
	BEGIN
		PRINT N'Feedback mode only.  New data will not be comitted.'
		PRINT N'Set parameter @ptiIsFeedbackOnly = 0 to enable comitting of any new data in [IFA].[stat].[StatGroup].'
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
		PRINT N'_DO_NOT_ run this sproc if you are not the custodian of the content in [PrdBi02].[Stat].[stat].[StatGroup].'
		PRINT N'Aborting sproc execution.'
		
		IF @tiIsFeedbackOnly = 0 
			RETURN (-1) -- if not feedback only mode, then the sproc stops here.
	END
	
	IF @pnvStatGroupId IS NULL OR ( @pnvStatGroupId IS NOT NULL AND @pnvStatGroupId <> N'ALL' AND ISNUMERIC( @pnvStatGroupId ) = 0 )
	BEGIN
		PRINT N'No @pnvStatGroupId value has been supplied.'
		PRINT N'_DO_NOT_ run this sproc if you are not the custodian of the content in [PrdBi02].[Stat].[stat].[StatGroup].'
		PRINT N'@pnvStatGroupId must either be "ALL" or a valid StatGroupId that has not yet been migrated into [PrdTrx01].[IFA].[stat].[StatGroup].'
		PRINT N'Aborting sproc execution.'
			
		IF @tiIsFeedbackOnly = 0 
			RETURN (-1) -- if not feedback only mode, then the sproc stops here.
	END
	
	DROP TABLE IF EXISTS #tblNewStatGroup;

	SELECT
		 [StatGroupId]
		,[AncestorStatGroupId]
		,[OrgId]
		,[Name]
		,[Descr]
		,DateActivated = SYSDATETIME() --We want to track when the metadata was inserted in PrdTrx01.
	INTO #tblNewStatGroup
	FROM [PrdBi02].[Stat].[stat].[StatGroup] AS sg
	WHERE ( @pnvStatGroupId = N'ALL' OR ( ISNUMERIC( @pnvStatGroupId ) = 1 AND sg.[StatGroupId] = TRY_CONVERT( smallint, @pnvStatGroupId ) ) )
		AND sg.[StatGroupId] > 0
		AND sg.[AncestorStatGroupId] > 0
		AND sg.[OrgId] >= 0
		AND NOT EXISTS( SELECT 'X' FROM [IFA].[stat].[StatGroup] AS x WHERE x.[StatGroupId] = sg.[StatGroupId] )
	ORDER BY sg.[StatGroupId] ASC;

	SELECT @iSourceRecCount = COUNT(1) 
	FROM #tblNewStatGroup;

	PRINT N'CCF Reference: ' + @nvCCF;
	PRINT N'';
	PRINT CONVERT( nvarchar(10), @iSourceRecCount ) + N' new StatGroup rows found:';

	SELECT @nvNewStatList = @nvNewStatList
		+ NCHAR(013) + NCHAR(010)
		+ NCHAR(009) + ISNULL( TRY_CONVERT( nvarchar(max), [StatGroupId] ), N'{null}' ) 
		+ NCHAR(009) + ISNULL( TRY_CONVERT( nvarchar(max), [OrgId] ), N'{null}' ) 
		+ NCHAR(009) + N'"' + ISNULL( [Name], N'{null}' ) + N'"'
		+ NCHAR(009) + N'{' + ISNULL( TRY_CONVERT( nvarchar(max), [DateActivated], 121 ), N'{null}' ) + N'}'
	FROM #tblNewStatGroup
	ORDER BY StatGroupId ASC;

	PRINT @nvNewStatList;
	PRINT N'';

	IF @iSourceRecCount > 0
	BEGIN -- @iSourceRecCount > 0

		IF @tiIsFeedbackOnly = 0
		BEGIN
/* TO-DO: Enable the INSERT by disabling this comment block which is wrapped around said INSERT. */
			INSERT INTO [IFA].[stat].[StatGroup](
				 StatGroupId
				,AncestorStatGroupId
				,OrgId
				,Name
				,Descr
				,DateActivated
			)
--*/
			SELECT 
				 StatGroupId
				,AncestorStatGroupId
				,OrgId
				,Name
				,Descr
				,DateActivated
			FROM #tblNewStatGroup
			ORDER BY [StatGroupId] ASC;

			SET @iInsertRecCount = @@ROWCOUNT;
		
			IF @iInsertRecCount = @iSourceRecCount 
				PRINT N'All ' + CONVERT( nvarchar(10), @iInsertRecCount ) + N' new rows have been inserted into PrdTrx01.'; 
			ELSE 
				PRINT N'!!! Not all new rows were inserted into PrdTrx01 !!!';

		END
	
	END -- @iSourceRecCount > 0

	DROP TABLE IF EXISTS #tblNewStatGroup;

END -- [stat].[uspStatGroupPullNewFromPrdBi02]
;
