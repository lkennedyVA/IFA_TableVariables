USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspDangerousItemProcessTrim
	CreatedBy: Larry Dugger
	Date: 2017-08-24
	Description: This procedure will purge records older than @piPurgeHours
		We only look at Item and Process, assumming RPResult is on a much more recent Trim 
		range.

	Tables: [ifa].[Item]
		,[ifa].[Process]
	History:
		2017-08-24 - LBD - Created
		2025-01-09 - LXK - Replaced table variables for local temp tables
*****************************************************************************************/
ALTER PROCEDURE [ifa].[uspDangerousItemProcessTrim](
	 @piPurgeHours INT = -7800
	,@piBatchSize INT = 10000
	,@piRecordSetSize INT = 100000
)
AS
BEGIN
	SET NOCOUNT ON; 
	--THIS table holds a distinct set of rows up to @piRecordSetSize 
	drop table if exists #tblRecordSetSize
	create table #tblRecordSetSize(
		ItemId bigint primary key
		);	

	drop table if exists #tblToDelete
	create table #tblToDelete(
		ItemId bigint primary key
		); --THIS is a PageSize of rows up to @piPageSize
		
	drop table if exists #tblDeletedItem
	create table #tblDeletedItem(
		ProcessId bigint
		);  --THIS is a PageSize of rows up to @piPageSize

	DECLARE @dtPurge datetime2(7) = DateAdd(hour,@piPurgeHours,getdate())
		,@iRowCount int =0
		,@iRowsDeleted int = 0;

	--LOAD Distinct RecordSetSize
	INSERT INTO #tblRecordSetSize(ItemId)
	SELECT TOP (@piRecordSetSize) ItemId
	FROM [ifa].[Item] WITH (READUNCOMMITTED)
	WHERE DateActivated < @dtPurge
	ORDER BY ItemId;

	SET @iRowCount = @@ROWCOUNT;
	select @iRowCount, @dtPurge
	--Initially LOAD a page size of records
	INSERT INTO #tblToDelete(ItemId)
	SELECT TOP (@piBatchSize) ItemId
	FROM #tblRecordSetSize
	ORDER BY ItemId;
	SELECT @@ROWCOUNT

	IF EXISTS (SELECT 'X' FROM #tblRecordSetSize)
	BEGIN
		INSERT INTO [dbo].[ItemProcessTrimLog](Cnt, Msg, DateActivated)
		SELECT @iRowCount,'uspDangerousItemProcessTrim Enter',SYSDATETIME();
		WHILE 1 = 1 
		BEGIN
			--Delete a set of Collection
			DELETE c
			FROM [ifa].[Collection] c
			INNER JOIN #tblToDelete td on c.ItemId = td.ItemId;
			--Delete a set of CustomerItemReturn
			DELETE cir
			FROM [common].[CustomerItemReturn] cir
			INNER JOIN #tblToDelete td on cir.ItemId = td.ItemId;
			--Delete a set of Image
			DELETE i
			FROM [ifa].[Image] i
			INNER JOIN #tblToDelete td on i.ItemId = td.ItemId;
			--Delete a set of Return
			DELETE r
			FROM [ifa].[Return] r
			INNER JOIN #tblToDelete td on r.ItemId = td.ItemId;
			--Delete a set of RuleBreakData
			DELETE rbd
			FROM [ifa].[RuleBreakData] rbd
			INNER JOIN #tblToDelete td on rbd.ItemId = td.ItemId;
			--Delete a set of Items
			DELETE i
				OUTPUT deleted.ProcessId
				INTO #tblDeletedItem
			FROM [ifa].[Item] i
			INNER JOIN #tblToDelete td on i.ItemId = td.ItemId;
			--Delete a set of Device
			DELETE d2
			FROM [ifa].[Device] d2
			INNER JOIN #tblDeletedItem d on d2.ProcessId = d.ProcessId;
			--Delete a set of Misc
			DELETE m
			FROM [ifa].[Misc] m
			INNER JOIN #tblDeletedItem d on m.ProcessId = d.ProcessId;
			--Delete the associated Process records
			DELETE p
			FROM [ifa].[Process] p
			INNER JOIN #tblDeletedItem d on p.ProcessId = d.ProcessId
			WHERE NOT EXISTS (SELECT 'X' FROM [ifa].[Item] WITH (READUNCOMMITTED) WHERE p.ProcessId = ProcessId);
			
			SET @iRowCount = @@ROWCOUNT;
			SET @iRowsDeleted += @iRowCount;

			--REMOVE what we just worked from source
			DELETE rss
			FROM #tblRecordSetSize rss
			INNER JOIN #tblToDelete td on rss.ItemId = td.ItemId;

			--CLEAN work table
			DELETE FROM #tblToDelete;--Clear Our Table
			--CLEAN tracking table
			DELETE FROM #tblDeletedItem;

			--LOAD a page size of records
			INSERT INTO #tblToDelete(ItemId)
			SELECT top (@piBatchSize) ItemId
			FROM #tblRecordSetSize
			ORDER BY ItemId;

			SET @iRowCount = @@ROWCOUNT;

			--How many did are left, if none, we are done
			IF @iRowCount = 0
				BREAK
			--ELSE IF CONVERT(TIME,GETDATE()) BETWEEN '5:00 AM' AND '11:59 PM'
			--	BREAK
			WAITFOR DELAY '00:00:01'

			SET @iRowCount = 0;
		END
		INSERT INTO [dbo].[ItemProcessTrimLog](Cnt, Msg, DateActivated)
		SELECT @iRowsDeleted,'uspDangerousItemProcessTrim Exit',SYSDATETIME();
	END

END
