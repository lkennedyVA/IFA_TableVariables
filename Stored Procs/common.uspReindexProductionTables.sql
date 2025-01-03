USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/****************************************************************************************
	Name: uspReindexProductionTables
	CreatedBy: Larry Dugger
	Date: 2014-12-16
	Description: This procedure will 
		reorganize indexes on tables that have a fragmentation level between 5 and 30%
		rebuild indexes (online) on tables with fragmentation > 30%
	History:
		2015-11-04 - LBD - Created
		2016-08-17 - LBD - Modified, added compression, and @piScriptOnly
*****************************************************************************************/
ALTER PROCEDURE [common].[uspReindexProductionTables]
	@piExecute INT = 0
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @dtReferenceDate datetime2(7) 
		,@iObjectId int
		,@iIndexId int
		,@iPartitionCount bigint
		,@nvSchemaName nvarchar(130)
		,@nvObjectName nvarchar(130)
		,@nvIndexName nvarchar(130)
		,@biPartitionNum bigint
		,@biPartitions bigint
		,@fFragment float
		,@iPageCount int
		,@nvRebuildType nvarchar(255)
		,@nvCmd nvarchar(4000)
		,@iPageCountMinimum smallint = 50
		,@fFragmentmentationMinimum float = 5.0
		,@fFragmentmentationMaximum float = 30.0
	DECLARE @Biscuit table(
		 ObjectName nvarchar(130)
		,SchemaName nvarchar(130)
		,IndexName nvarchar(130)
		,PartitionCnt bigint
		,Frag float
		,PageCount bigint
		,RebuildType nvarchar(255)
	);
	DECLARE @Reference table(
		 Id int identity(1,1)
		 ,Cmd nvarchar(4000)
		,TimeLapse nvarchar(10)
	);
	DECLARE @SQLCmd table(
		SQLCMD nvarchar(512)
	);
	-- Conditionally select tables and indexes from the sys.dm_db_index_physical_stats function
	-- and convert object and index IDs to names.
	INSERT INTO @Biscuit(ObjectName,SchemaName,IndexName,PartitionCnt,Frag,PageCount,RebuildType)
	SELECT distinct QUOTENAME(o.name), QUOTENAME(s2.name), QUOTENAME(i.name), 
		PartCnt,avg_fragmentation_in_percent,page_count,
		CASE WHEN avg_fragmentation_in_percent < @fFragmentmentationMaximum THEN N'REORGANIZE;--'
			ELSE N'REBUILD WITH ( PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON, ONLINE = ON, SORT_IN_TEMPDB = ON'
				+ CASE WHEN p.[data_compression] = 0 THEN ', DATA_COMPRESSION = NONE);--' 
						WHEN p.[data_compression] = 1 THEN ', DATA_COMPRESSION = ROW);--' 
						WHEN p.[data_compression] = 2 THEN ', DATA_COMPRESSION = PAGE);--' 
						WHEN p.[data_compression] = 3 THEN ', DATA_COMPRESSION = COLUMNSTORE );--' 
						WHEN p.[data_compression] = 4 THEN ', DATA_COMPRESSION = COLUMNSTORE_ARCHIVE );--'END
		END
	FROM sys.dm_db_index_physical_stats (DB_ID(), NULL, NULL , NULL, 'LIMITED') s
	INNER JOIN sys.objects o on s.object_id = o.object_id
	INNER JOIN sys.schemas s2 ON o.schema_id = s2.schema_id
	INNER JOIN sys.indexes i ON o.object_id = i.object_id
									AND s.index_id = i.index_id
	LEFT JOIN (SELECT COUNT(*) as PartCnt,[data_compression], object_id, index_id 
				FROM sys.partitions 
				GROUP BY object_id, [data_compression], index_id) p on o.object_id = p.object_id 
																	AND p.Index_id = i.Index_id
	WHERE avg_fragmentation_in_percent > @fFragmentmentationMinimum
		AND s.index_id > 0
		AND page_count > @iPageCountMinimum;
	INSERT INTO @Biscuit(ObjectName,SchemaName,IndexName,RebuildType)
	SELECT QUOTENAME([so].[name]), QUOTENAME([sch].[name]), QUOTENAME([ss].[name]), 'STATISTICS'
	FROM [sys].[stats] [ss]
	INNER JOIN [sys].[objects] [so] ON [ss].[object_id] = [so].[object_id]
	INNER JOIN [sys].[schemas] [sch] ON [so].[schema_id] = [sch].[schema_id]
	OUTER APPLY [sys].[dm_db_stats_properties]
							  ([so].[object_id], [ss].[stats_id]) sp
	WHERE [so].[type] = 'U'
		AND [sp].[rows_sampled] > 1000
		AND CAST(100 * [sp].[modification_counter] / [sp].[rows]
															 AS DECIMAL(18,2)) >= 5.00
		--AND NOT EXISTS (SELECT 'x' FROM @Biscuit 
		--						WHERE QUOTENAME([sch].[name]) = SchemaName 
		--							AND QUOTENAME([so].[name]) = ObjectName
		--							AND QUOTENAME([ss].[name]) = IndexName)
	ORDER BY CAST(100 * [sp].[modification_counter] / [sp].[rows]
														 AS DECIMAL(18,2)) DESC;
	-- Declare the cursor for the list of partitions to be processed.
	DECLARE csr_partitions CURSOR FOR SELECT * FROM @Biscuit;
	-- Open the cursor.
	OPEN csr_partitions;
	FETCH csr_partitions INTO @nvObjectName, @nvSchemaName, @nvIndexName, @biPartitionNum, @fFragment, @iPageCount, @nvRebuildType;
	-- Loop through the partitions.
	WHILE  @@FETCH_STATUS = 0
	BEGIN
		IF @nvRebuildType <> 'Statistics'
		BEGIN
			SET @nvCmd = N'ALTER INDEX ' + @nvIndexName + N' ON ' + @nvSchemaName + N'.' + @nvObjectName +' ' +@nvRebuildType+CONVERT(NVARCHAR(10),@fFragment);
			IF @iPartitionCount > 1
			SET @nvCmd = @nvCmd + N' PARTITION=' + CAST(@biPartitionNum AS nvarchar(10));
		END
		ELSE
			SET @nvCmd = N'UPDATE STATISTICS ' + @nvSchemaName + N'.' + @nvObjectName + ' ' + @nvIndexName
		--IF @nvSchemaName <> '[archive]'
		BEGIN
			SET @dtReferenceDate = SYSDATETIME();
			IF ISNULL(@piExecute,0) = 1
			BEGIN
				EXECUTE (@nvCmd);
				EXECUTE ('Checkpoint');
			END
			INSERT INTO @Reference(Cmd,TimeLapse)
			SELECT @nvCmd, CONVERT(NVARCHAR(10),DATEDIFF(SECOND,@dtReferenceDate,SYSDATETIME()));
			INSERT INTO @Reference(Cmd,TimeLapse)
			SELECT 'Checkpoint',CONVERT(NVARCHAR(10),DATEDIFF(SECOND,@dtReferenceDate,SYSDATETIME()));
		END
		FETCH csr_partitions INTO @nvObjectName, @nvSchemaName, @nvIndexName, @biPartitionNum, @fFragment, @iPageCount, @nvRebuildType;
	END;
	-- Close and deallocate the cursor.
	CLOSE csr_partitions;
	DEALLOCATE csr_partitions;
	SELECT Cmd,Timelapse 
	FROM @Reference
	order by Id;
END