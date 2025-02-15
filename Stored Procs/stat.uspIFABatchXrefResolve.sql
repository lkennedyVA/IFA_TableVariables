USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [stat].[uspIFABatchXrefResolve]
	(
		 @pvErrorMessage varchar(255) OUTPUT
	)
AS
/****************************************************************************************
	Name: [stat].[uspIFABatchXrefResolve]
	Created By: LWhiting
	Date: 2024-10-12

	This sproc compares the cross-reference [stat].[IFABatchXref] against the [IFA].[stat].{StatType%} tables.

		* Determines if a batch Id no longer exists in any of the [IFA].[stat].{StatType%} tables.
			** if no longer in use, the sproc makes individual calls of [Condensed].[stat].[uspIFABatchXrefRetire] for each such batch Id
				*** @pvErrorMessage returns the error message text

		* TO-DO: After initial deployment, return to this sproc and add the reverse check: batch Id's found in [IFA] yet not found in [Condensed].[stat].[IFABatchXref].
			** since we have all the [IFA] batch Id's consolidated in a temp table, now would be a good time to perform this reverse check (otherwise we'd have to collect all the batch Id's, again, somewhere else).
			** how do we want to deal with this situation should it arise?

		* This sproc returns {@pvErrorMessage = ""} aka "success", whether any batch Id's are retired or not.


	History:
		2024-10-12 - LWhiting - Created
*****************************************************************************************/
BEGIN

	SET NOCOUNT ON
	;

	DECLARE @iErrorDetailId int --2024-09-20
		,@sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME( @@PROCID ) --2024-09-20
		,@nvObjectName nvarchar(128) = TRY_CONVERT( nvarchar(128), OBJECT_NAME( @@PROCID ) )
		,@iReturn int = 0 -- 0 = Success, !0 = Issue encountered
		,@iCollectFailCount int = 0
		,@nvDatatype nvarchar(32) = NULL
		,@iSourceBatchId int = NULL
		,@vBatchSource varchar(32) = NULL
		,@iIFABatchSeq int = NULL
		,@iIFABatchId int = NULL
		,@iIFABatchVersionSeq int = NULL
		,@iRecCount int = 0
		,@iRetireSeqMax int = NULL
		,@iRetireSeq int = NULL
		,@vErrorMessage varchar(255) = @pvErrorMessage
		,@nvThisObjectInstance nvarchar(4000) = NULL
		,@nvMessage nvarchar(4000) = NULL
		,@nvProfileName nvarchar(128) = ( SELECT TOP 1 ProfileName = smp.name FROM msdb.dbo.sysmail_profile AS smp ORDER BY smp.profile_id )
		,@nvFrom nvarchar(max) = ( SELECT TOP 1 AccountFromAddress = sma.email_address FROM msdb.dbo.sysmail_account sma ORDER BY account_id )
		,@nvRecipients nvarchar(max) = 'DataServices@validadvantage.com'
		,@nvSubject nvarchar(255) = NULL
		,@nvBody nvarchar(max) = N''
		,@nvCRLF nvarchar(2) = NCHAR(013) + NCHAR(010)
	;

	SET @nvThisObjectInstance = [dbo].[ufnObjectExecutionIdentifierString]( @@PROCID, @@SPID, DB_ID() )
	;
	SET @nvMessage = @nvThisObjectInstance + N' BEGIN PROC...'
	;
	PRINT @nvMessage
	;
	INSERT INTO [dbo].[StatLog]( [Message] )
	SELECT @nvMessage
	;


/*
	The "live" situation means populating #BatchIdFromEachStatType from all the StatType% tables.
	The 'dev/test' situation means either populating #BatchIdFromEachStatType from all the StatType% tables OR populating from the dev/test table [IFA].[stat].[BatchIdStatTypeList_WIP_LSW].
	
	Using [IFA].[stat].[BatchIdStatTypeList_WIP_LSW] gives us a shortcut to avoid waiting 20-to-50 minutes for collecting from all the StatType% tables.
	Of course, this means the content of [IFA].[stat].[BatchIdStatTypeList_WIP_LSW] has to be managed in whatever manner meets the dev/test needs.

*/
DROP TABLE IF EXISTS #BatchIdFromEachStatType
;
CREATE TABLE #BatchIdFromEachStatType ( [BatchLogId] int, [StatType] varchar(32), [RecCount] bigint )
;

DROP TABLE IF EXISTS #BatchIdList
;
CREATE TABLE #BatchIdList ( [BatchLogId] int, [RecCount] bigint )
;

DROP TABLE IF EXISTS #RetireBatchIdList
;
CREATE TABLE #RetireBatchIdList ( [RetireSeq] int IDENTITY(1,1), [BatchLogId] int )
;


--/ *
PRINT CONVERT( varchar(50), SYSDATETIME(), 121 )
;
PRINT 'Collect batch IDs: Begin... (note: collecting batch IDs could take from 20 to 60+ minutes)'
;
RAISERROR ( '', 0, 1 ) WITH NOWAIT
;

SET @nvDatatype = 'Bigint'
;
PRINT CHAR(009) + CONVERT( varchar(50), SYSDATETIME(), 121 ) + CHAR(009) + @nvDatatype + '...'
;
RAISERROR ( '', 0, 1 ) WITH NOWAIT
;
BEGIN TRY
	INSERT INTO #BatchIdFromEachStatType ( [BatchLogId], [StatType], [RecCount] )
	SELECT [BatchLogId], StatType = @nvDatatype, [RecCount] FROM ( SELECT [BatchLogId], RecCount = COUNT(1) FROM [stat].[StatTypeBigint] WITH (READUNCOMMITTED) GROUP BY [BatchLogId] ) AS b
	--WHERE NOT EXISTS( SELECT 'X' FROM #BatchIdFromEachStatType AS x WHERE x.[BatchLogId] = b.[BatchLogId] )
	ORDER BY [BatchLogId]
	;
END TRY
BEGIN CATCH
	SET @iCollectFailCount = @iCollectFailCount + 1
	;

	SET @nvMessage = @nvThisObjectInstance + N' WARN: Could not collect batch IDs from [IFA].[stat].[StatType' + @nvDatatype + N']'
	;
	PRINT @nvMessage
	;
	INSERT INTO [dbo].[StatLog]( [Message] )
	SELECT @nvMessage
	;
END CATCH

SET @nvDatatype = 'Bit'
;
PRINT CHAR(009) + CONVERT( varchar(50), SYSDATETIME(), 121 ) + CHAR(009) + @nvDatatype + '...'
;
RAISERROR ( '', 0, 1 ) WITH NOWAIT
;
BEGIN TRY
	INSERT INTO #BatchIdFromEachStatType ( [BatchLogId], [StatType], [RecCount] )
	SELECT [BatchLogId], StatType = @nvDatatype, [RecCount] FROM ( SELECT [BatchLogId], RecCount = COUNT(1) FROM [stat].[StatTypeBit] WITH (READUNCOMMITTED) GROUP BY [BatchLogId] ) AS b
	--WHERE NOT EXISTS( SELECT 'X' FROM #BatchIdFromEachStatType AS x WHERE x.[BatchLogId] = b.[BatchLogId] )
	ORDER BY [BatchLogId]
	;
END TRY
BEGIN CATCH
	SET @iCollectFailCount = @iCollectFailCount + 1

	SET @nvMessage = @nvThisObjectInstance + N' WARN: Could not collect batch IDs from [IFA].[stat].[StatType' + @nvDatatype + N']'
	;
	PRINT @nvMessage
	;
	INSERT INTO [dbo].[StatLog]( [Message] )
	SELECT @nvMessage
	;
END CATCH

SET @nvDatatype = 'Date'
;
PRINT CHAR(009) + CONVERT( varchar(50), SYSDATETIME(), 121 ) + CHAR(009) + @nvDatatype + '...'
;
RAISERROR ( '', 0, 1 ) WITH NOWAIT
;
BEGIN TRY
	INSERT INTO #BatchIdFromEachStatType ( [BatchLogId], [StatType], [RecCount] )
	SELECT [BatchLogId], StatType = @nvDatatype, [RecCount] FROM ( SELECT [BatchLogId], RecCount = COUNT(1) FROM [stat].[StatTypeDate] WITH (READUNCOMMITTED) GROUP BY [BatchLogId] ) AS b
	--WHERE NOT EXISTS( SELECT 'X' FROM #BatchIdFromEachStatType AS x WHERE x.[BatchLogId] = b.[BatchLogId] )
	ORDER BY [BatchLogId]
	;
END TRY
BEGIN CATCH
	SET @iCollectFailCount = @iCollectFailCount + 1

	SET @nvMessage = @nvThisObjectInstance + N' WARN: Could not collect batch IDs from [IFA].[stat].[StatType' + @nvDatatype + N']'
	;
	PRINT @nvMessage
	;
	INSERT INTO [dbo].[StatLog]( [Message] )
	SELECT @nvMessage
	;
END CATCH

SET @nvDatatype = 'Decimal1602'
;
PRINT CHAR(009) + CONVERT( varchar(50), SYSDATETIME(), 121 ) + CHAR(009) + @nvDatatype + '...'
;
RAISERROR ( '', 0, 1 ) WITH NOWAIT
;
BEGIN TRY
	INSERT INTO #BatchIdFromEachStatType ( [BatchLogId], [StatType], [RecCount] )
	SELECT [BatchLogId], StatType = @nvDatatype, [RecCount] FROM ( SELECT [BatchLogId], RecCount = COUNT(1) FROM [stat].[StatTypeDecimal1602] WITH (READUNCOMMITTED) GROUP BY [BatchLogId] ) AS b
	--WHERE NOT EXISTS( SELECT 'X' FROM #BatchIdFromEachStatType AS x WHERE x.[BatchLogId] = b.[BatchLogId] )
	ORDER BY [BatchLogId]
	;
END TRY
BEGIN CATCH
	SET @iCollectFailCount = @iCollectFailCount + 1

	SET @nvMessage = @nvThisObjectInstance + N' WARN: Could not collect batch IDs from [IFA].[stat].[StatType' + @nvDatatype + N']'
	;
	PRINT @nvMessage
	;
	INSERT INTO [dbo].[StatLog]( [Message] )
	SELECT @nvMessage
	;
END CATCH

SET @nvDatatype = 'Int'
;
PRINT CHAR(009) + CONVERT( varchar(50), SYSDATETIME(), 121 ) + CHAR(009) + @nvDatatype + '...'
;
RAISERROR ( '', 0, 1 ) WITH NOWAIT
;
BEGIN TRY
	INSERT INTO #BatchIdFromEachStatType ( [BatchLogId], [StatType], [RecCount] )
	SELECT [BatchLogId], StatType = @nvDatatype, [RecCount] FROM ( SELECT [BatchLogId], RecCount = COUNT(1) FROM [stat].[StatTypeInt] WITH (READUNCOMMITTED) GROUP BY [BatchLogId] ) AS b
	--WHERE NOT EXISTS( SELECT 'X' FROM #BatchIdFromEachStatType AS x WHERE x.[BatchLogId] = b.[BatchLogId] )
	ORDER BY [BatchLogId]
	;
END TRY
BEGIN CATCH
	SET @iCollectFailCount = @iCollectFailCount + 1

	SET @nvMessage = @nvThisObjectInstance + N' WARN: Could not collect batch IDs from [IFA].[stat].[StatType' + @nvDatatype + N']'
	;
	PRINT @nvMessage
	;
	INSERT INTO [dbo].[StatLog]( [Message] )
	SELECT @nvMessage
	;
END CATCH

SET @nvDatatype = 'NChar100'
;
PRINT CHAR(009) + CONVERT( varchar(50), SYSDATETIME(), 121 ) + CHAR(009) + @nvDatatype + '...'
;
RAISERROR ( '', 0, 1 ) WITH NOWAIT
;
BEGIN TRY
	INSERT INTO #BatchIdFromEachStatType ( [BatchLogId], [StatType], [RecCount] )
	SELECT [BatchLogId], StatType = @nvDatatype, [RecCount] FROM ( SELECT [BatchLogId], RecCount = COUNT(1) FROM [stat].[StatTypeNChar100] WITH (READUNCOMMITTED) GROUP BY [BatchLogId] ) AS b
	--WHERE NOT EXISTS( SELECT 'X' FROM #BatchIdFromEachStatType AS x WHERE x.[BatchLogId] = b.[BatchLogId] )
	ORDER BY [BatchLogId]
	;
END TRY
BEGIN CATCH
	SET @iCollectFailCount = @iCollectFailCount + 1

	SET @nvMessage = @nvThisObjectInstance + N' WARN: Could not collect batch IDs from [IFA].[stat].[StatType' + @nvDatatype + N']'
	;
	PRINT @nvMessage
	;
	INSERT INTO [dbo].[StatLog]( [Message] )
	SELECT @nvMessage
	;
END CATCH

SET @nvDatatype = 'NChar50'
;
PRINT CHAR(009) + CONVERT( varchar(50), SYSDATETIME(), 121 ) + CHAR(009) + @nvDatatype + '...'
;
RAISERROR ( '', 0, 1 ) WITH NOWAIT
;
BEGIN TRY
	INSERT INTO #BatchIdFromEachStatType ( [BatchLogId], [StatType], [RecCount] )
	SELECT [BatchLogId], StatType = @nvDatatype, [RecCount] FROM ( SELECT [BatchLogId], RecCount = COUNT(1) FROM [stat].[StatTypeNChar50] WITH (READUNCOMMITTED) GROUP BY [BatchLogId] ) AS b
	--WHERE NOT EXISTS( SELECT 'X' FROM #BatchIdFromEachStatType AS x WHERE x.[BatchLogId] = b.[BatchLogId] )
	ORDER BY [BatchLogId]
	;
END TRY
BEGIN CATCH
	SET @iCollectFailCount = @iCollectFailCount + 1

	SET @nvMessage = @nvThisObjectInstance + N' WARN: Could not collect batch IDs from [IFA].[stat].[StatType' + @nvDatatype + N']'
	;
	PRINT @nvMessage
	;
	INSERT INTO [dbo].[StatLog]( [Message] )
	SELECT @nvMessage
	;
END CATCH

SET @nvDatatype = 'Numeric0109'
;
PRINT CHAR(009) + CONVERT( varchar(50), SYSDATETIME(), 121 ) + CHAR(009) + @nvDatatype + '...'
;
RAISERROR ( '', 0, 1 ) WITH NOWAIT
;
BEGIN TRY
	INSERT INTO #BatchIdFromEachStatType ( [BatchLogId], [StatType], [RecCount] )
	SELECT [BatchLogId], StatType = @nvDatatype, [RecCount] FROM ( SELECT [BatchLogId], RecCount = COUNT(1) FROM [stat].[StatTypeNumeric0109] WITH (READUNCOMMITTED) GROUP BY [BatchLogId] ) AS b
	--WHERE NOT EXISTS( SELECT 'X' FROM #BatchIdFromEachStatType AS x WHERE x.[BatchLogId] = b.[BatchLogId] )
	ORDER BY [BatchLogId]
	;
END TRY
BEGIN CATCH
	SET @iCollectFailCount = @iCollectFailCount + 1

	SET @nvMessage = @nvThisObjectInstance + N' WARN: Could not collect batch IDs from [IFA].[stat].[StatType' + @nvDatatype + N']'
	;
	PRINT @nvMessage
	;
	INSERT INTO [dbo].[StatLog]( [Message] )
	SELECT @nvMessage
	;
END CATCH

SET @nvDatatype = 'Numeric1604'
;
PRINT CHAR(009) + CONVERT( varchar(50), SYSDATETIME(), 121 ) + CHAR(009) + @nvDatatype + '...'
;
RAISERROR ( '', 0, 1 ) WITH NOWAIT
;
BEGIN TRY
	INSERT INTO #BatchIdFromEachStatType ( [BatchLogId], [StatType], [RecCount] )
	SELECT [BatchLogId], StatType = @nvDatatype, [RecCount] FROM ( SELECT [BatchLogId], RecCount = COUNT(1) FROM [stat].[StatTypeNumeric1604] WITH (READUNCOMMITTED) GROUP BY [BatchLogId] ) AS b
	--WHERE NOT EXISTS( SELECT 'X' FROM #BatchIdFromEachStatType AS x WHERE x.[BatchLogId] = b.[BatchLogId] )
	ORDER BY [BatchLogId]
	;
END TRY
BEGIN CATCH
	SET @iCollectFailCount = @iCollectFailCount + 1

	SET @nvMessage = @nvThisObjectInstance + N' WARN: Could not collect batch IDs from [IFA].[stat].[StatType' + @nvDatatype + N']'
	;
	PRINT @nvMessage
	;
	INSERT INTO [dbo].[StatLog]( [Message] )
	SELECT @nvMessage
	;
END CATCH

PRINT 'Collect batch IDs: ...done.'
;
PRINT CONVERT( varchar(50), SYSDATETIME(), 121 )
;
PRINT ''
;

IF @iCollectFailCount > 0
BEGIN
		
		SET @iReturn = ( -1 * @iCollectFailCount )
		;
		SET @nvMessage = 'Failed to collect from ' + ISNULL( TRY_CONVERT( varchar(20), @iCollectFailCount ), '{collectFailCount:null}' ) + ' [IFA].[stat].StatType% tables.'
			+ SPACE(20) + 'Cannot proceed with next steps in ' + @sSchemaName + '.' + @nvObjectName
		;
		PRINT @nvMessage
		;

		SET @nvMessage = @nvThisObjectInstance + N' ALERT: ' + @nvMessage
		;
		PRINT @nvMessage
		;
		INSERT INTO [dbo].[StatLog]( [Message] )
		SELECT @nvMessage
		;

		SELECT @nvSubject = N'WARN: IFABatchXref - Could not collect batch IDs from all [IFA].[stat].StatType% tables.'
			,@nvBody = ( @@SERVERNAME + SPACE(1) + DB_NAME() + N'.' + @sSchemaName + N'.' + @nvObjectName + @nvCRLF + @nvCRLF 
					+ @nvMessage + @nvCRLF + @nvCRLF 
					+ N'{MT:' + TRY_CONVERT( nvarchar(50), NEWID() ) + '}' -- Message Tag
				)
		;
		EXEC msdb.dbo.sp_send_dbmail 
			 @profile_name = @nvProfileName
			,@from_address = @nvFrom
			,@recipients = @nvRecipients
			,@subject = @nvSubject
			,@body = @nvBody
			,@body_format = 'TEXT'
			--,@importance = 'High'
		;

		SET @pvErrorMessage = @nvMessage
		;
		RETURN ( @iReturn ) -- uncomment when in SPROC form. -- we are not a real error, therefore we must be {@iReturn = 0}.
		;
		SET NOEXEC ON -- We can't RETURN from a dev.script.  But, we can stop execution dead in its tracks.
		;
	
END
;
--* /

/* if using the above collection code, then do not use this substitute dev/test code...

INSERT INTO #BatchIdFromEachStatType ( [BatchLogId], [StatType], [RecCount] )
SELECT [BatchLogId], [StatType], [RecCount] FROM [IFA].[stat].[BatchIdStatTypeList_WIP_LSW] ORDER BY [BatchLogId], [StatType]
;

*/

-- populate a concise list of batch Id's into #BatchIdList from #BatchIdFromEachStatType
INSERT INTO #BatchIdList ( [BatchLogId], [RecCount] )
SELECT [BatchLogId], RecCount = SUM( [RecCount] ) FROM #BatchIdFromEachStatType GROUP BY [BatchLogId] ORDER BY [BatchLogId]
;


-- purge older than 1 year
delete from [Condensed].[stat].[IFABatchXrefResolveCollectionHistory] where [CollectionDatetime] < dateadd( year, 1, sysdatetime() )
;
-- capture the latest
insert into [Condensed].[stat].[IFABatchXrefResolveCollectionHistory] ( [BatchLogId], [RecCount] )
select [BatchLogId], [RecCount]
from #BatchIdList
order by [BatchLogId]
;


	BEGIN TRY

		/*
		PRINT '...retirement code goes here...'
		;
		select [Batch Ids no longer in IFA StatType tables] = '', b.* from [Condensed].[stat].[IFABatchXref] as b 
		where b.[IFABatchId] is not null and not exists( select 'X' from #BatchIdList as x where b.[IFABatchId] = x.[BatchLogId] )
		;
		*/
		INSERT INTO #RetireBatchIdList ( [BatchLogId] )
		SELECT b.[IFABatchId] FROM [Condensed].[stat].[IFABatchXref] AS b 
		WHERE b.[IFABatchId] IS NOT NULL AND NOT EXISTS( SELECT 'X' FROM #BatchIdList AS x WHERE b.[IFABatchId] = x.[BatchLogId] )
		;
		SET @iRecCount = @@ROWCOUNT
		;
		SELECT 
			 @iRetireSeq = MIN( [RetireSeq] ) - 1 
			,@iRetireSeqMax = MAX( [RetireSeq] ) 
		FROM #RetireBatchIdList
		;
		SET @iRetireSeq = ISNULL( @iRetireSeq, 0 )
		SET @iRetireSeqMax = ISNULL( @iRetireSeqMax, 0 )
		;
		
		SET @nvMessage = CONVERT( varchar(20), @iRetireSeqMax ) + ' batch IDs to retire in [Condensed].[stat].[IFABatchXref].'
		;
		PRINT @nvMessage
		;

		SET @nvMessage = @nvThisObjectInstance + N' EFFORT: ' + @nvMessage
		;
		INSERT INTO [dbo].[StatLog]( [Message] )
		SELECT @nvMessage
		;

		IF @@SERVERNAME = N'FWUSDEVDB02'
		BEGIN
			IF @iRetireSeqMax > 10 
			BEGIN 
				SET @iRetireSeqMax = 10
				;
				PRINT CHAR(009) + '...Limiting dev/test iterations to 10 rows (setting @iRetireSeqMax = 10)...'
				;
			END
		END
		;

		PRINT ''
		;
		SET @iReturn = 0
		;
;
		WHILE @iRecCount > 0 AND @iRetireSeq < @iRetireSeqMax -- AND @iReturn = 0
		BEGIN
			SELECT 
				 @iRetireSeq = MIN( [RetireSeq] )
			FROM #RetireBatchIdList
			WHERE [RetireSeq] > @iRetireSeq
			;
			SELECT @iIFABatchId = [BatchLogId] 
			FROM #RetireBatchIdList
			WHERE [RetireSeq] = @iRetireSeq
			;
			SET @nvMessage = 'IFA batch ID ' + CONVERT( varchar(20), @iIFABatchId ) + ' (' + /*RIGHT( REPLICATE( SPACE(1), 5 ) +*/ CONVERT( varchar(5), @iRetireSeq ) /*, 5 )*/ + '/' + /*RIGHT( REPLICATE( SPACE(1), 5 ) +*/ CONVERT( varchar(5), @iRetireSeqMax ) /*, 5 )*/ + ')'
			;
			PRINT @nvMessage
			;

			SET @nvMessage = @nvThisObjectInstance + N' RETIRE: ' + @nvMessage
			;
			INSERT INTO [dbo].[StatLog]( [Message] )
			SELECT @nvMessage
			;

			IF RIGHT( @@SERVERNAME, 8 ) = N'PRDTRX01' -- Production
			BEGIN
				EXEC @iReturn = [Condensed].[stat].[uspIFABatchXrefRetire] @piIFABatchId = @iIFABatchId
				;
			END
			ELSE IF @@SERVERNAME = N'FWUSDEVDB02' -- Development
			BEGIN
				PRINT N'This is where we would call [Condensed].[stat].[uspIFABatchXrefRetire] @piIFABatchId = ' + ISNULL( TRY_CONVERT( nvarchar(20), @iIFABatchId ), N'{null}' )	-- EXEC @iReturn = [Condensed].[stat].[uspIFABatchXrefRetire] @piIFABatchId = @iIFABatchId
			END
			ELSE PRINT N'We have no idea where we are running.'
			;

		END
		;

/* TO-DO: 

	Since we already have all the existing batch Id's collected in a temp table (pulled from the relevant [IFA].[stat].[StatType%] tables),
		we might as well also check the opposite.  ie: "which batch Id's are in [IFA] yet missing in [Condensed].[stat].[IFABatchXref]"

	!!! BUT, COME BACK AND ADD THIS AFTER DEPLOYING THE INITIAL GOAL.

select [Batch Ids in IFA StatType tables missing in Condensed IFABatchXref] = '', b.* from #BatchIdList as b where b.[BatchLogId] is not null and not exists( select 'X' from [Condensed].[stat].[IFABatchXref] as x where b.[BatchLogId] = x.[IFABatchId] )
;
		-- call [Condensed].[stat].[uspIFABatchXref???] for each batch Id in [stat].[IFABatchXref] no longer found in the [IFA].[stat].{StatType%} tables.

*/

	END TRY
	BEGIN CATCH

		/*
		SET @iReturn = -1 -- only makes sense if we decide to not THROW
		;

		PRINT ''
		;
		PRINT '...error handling code goes here...'
		;
		SET @vErrorMessage = 'Some error message constructed from the internal supporting error functions of SQL Server.'
		;
		PRINT @vErrorMessage
		;
		SET @pvErrorMessage = CASE WHEN @iReturn = 0 THEN '' ELSE @vErrorMessage END 
		;

		THROW -- to throw or not to throw
		;
		*/
		
		--SET @iReturn = -1 -- only makes sense if we decide to not THROW --2024-09-20 .Lee, double check me on this.  Do we want to set @iReturn = -1 if we are THROW-ing?
		--;
		
		SET @pvErrorMessage = 'Failed to insert new row in [stat].[IFABatchXrefHistory] for IFABatchId ' + ISNULL( CONVERT( varchar(20), @iIFABatchId ), '{null}' ) 
				+ ' and IFABatchVersionSeq ' + ISNULL( CONVERT( varchar(20), @iIFABatchVersionSeq ), '{null}' ) 
				+ '.'
		;
		PRINT @pvErrorMessage
		;
	
		--PRINT '...error handling code goes here...'
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId = @iErrorDetailId OUTPUT --2024-09-20
		; 
		SET @iErrorDetailId = -1 * @iErrorDetailId --return the errordetailid negative (indicates an error occurred) --2024-09-20
		; 
		THROW -- to throw or not to throw
		;


	END CATCH
	;

	SET @pvErrorMessage = CASE WHEN @iReturn = 0 THEN '' ELSE @vErrorMessage END 
	;

	SET @nvMessage = @nvThisObjectInstance + N' ...END PROC'
	;
	PRINT @nvMessage
	;
	INSERT INTO [dbo].[StatLog]( [Message] )
	SELECT @nvMessage
	;

	RETURN ( @iReturn ) -- returns 0 if nothing got silly
	;

END
;
