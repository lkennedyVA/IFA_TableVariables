USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [financial].[uspLoadStatTypeIntToIFAStat]
	Created By: Larry Dugger
	Descr: Load the records from Work to Stat
			
	Tables: [IFA].[stat].[StatTypeInt]
		,[financial].[StatTypeInt]
	History:
		2019-02-16 - LBD - Created, complete re-write
*****************************************************************************************/
ALTER   PROCEDURE [financial].[uspLoadStatTypeIntToIFAStat](
	 @piPageSize INT = 10000
	,@pncDelay NCHAR(11) = '00:00:00.01'
)
AS
BEGIN
	SET NOCOUNT ON
	DECLARE @bEnableLog bit = 1
		,@iPageNumber int = 1
		,@iPageCount int = 1
		,@iPageSize int = @piPageSize
		,@ncDelay nchar(11) = @pncDelay
		,@bExists bit = 0
		,@nvMessage nvarchar(512)
		,@nvMessage2 nvarchar(512)
		,@dt datetime2(7) = sysdatetime()
		,@iErrorDetailId INT
		,@sSchemaName nvarchar(128)= OBJECT_SCHEMA_NAME( @@PROCID ); 

	SELECT @nvMessage = N'Executing ' 
	+ CASE 
		WHEN ( ISNULL( OBJECT_NAME( @@PROCID ), N'' ) = N'' ) 
			THEN N'a script ( ' + QUOTENAME( HOST_NAME() ) + N':' + QUOTENAME( SUSER_SNAME() ) + N' SPID=' + CONVERT( nvarchar(50), @@SPID ) + N' PROCID=' + CONVERT( nvarchar(50), @@PROCID ) + N' )' 
		ELSE N'database object ' + QUOTENAME( OBJECT_SCHEMA_NAME( @@PROCID ) ) + N'.' + QUOTENAME( OBJECT_NAME( @@PROCID ) ) 
		END + N' on ' + QUOTENAME( @@SERVERNAME ) + N'.' + QUOTENAME( DB_NAME() )
	WHERE @bExists = 1 
		AND @bEnableLog = 1;
	INSERT INTO [dbo].[StatLog]([Message])
	SELECT @nvMessage
	WHERE @bExists = 1 
		AND @bEnableLog = 1;

	BEGIN TRY
		--Any to Process 
		SELECT @bExists = 1
		FROM [financial].[StatTypeInt];

		SELECT @iPageCount = CEILING((COUNT(1)/(@iPageSize*1.0))) --returns same integer, or +1 if fraction exists
		FROM [financial].[StatTypeInt]
		WHERE @bExists = 1;

		SELECT @nvMessage2 = @nvMessage + ' PageCount Took '+convert(nvarchar(20),datediff(microsecond,@dt,sysdatetime()))+ ' mcs'
		WHERE @bExists = 1 
			AND @bEnableLog = 1;
		INSERT INTO [dbo].[StatLog]([Message])
		SELECT @nvMessage2
		WHERE @bExists = 1 
			AND @bEnableLog = 1;
		SET @dt = sysdatetime();

		--ADJUST the InsertFlag for the source table
		WHILE @bExists = 1
			AND @iPageNumber <= @iPageCount
		BEGIN	
			UPDATE src
				SET InsertFlag = 1
			FROM (SELECT PartitionId, KeyElementId, StatId, StatValue, BatchLogId, InsertFlag
						FROM [financial].[StatTypeInt]
						ORDER BY PartitionId, KeyElementId, StatId
						OFFSET @iPageSize * (@iPageNumber -1) ROWS
						FETCH NEXT @iPageSize ROWS ONLY) src
						WHERE NOT EXISTS (SELECT 'X' 
								FROM [IFA].[stat].[StatTypeInt] dst 
								WHERE src.PartitionId = dst.PartitionId
									AND src.KeyElementId = dst.KeyElementId
									AND src.StatId = dst.StatId);

			SELECT @nvMessage2 = @nvMessage + ' Update InsertFlag Page:'+convert(nvarchar(20),@iPageNumber)+ ' Took '+convert(nvarchar(20),datediff(microsecond,@dt,sysdatetime()))+ ' mcs'
			WHERE @bExists = 1 
				AND @bEnableLog = 1;
			INSERT INTO [dbo].[StatLog]([Message])
			SELECT @nvMessage2
			WHERE @bExists = 1 
				AND @bEnableLog = 1;
			SET @dt = sysdatetime();

			SET @iPageNumber += 1;
		END --Adjust the InsertFlag

		CREATE NONCLUSTERED INDEX [ixStatTypeInt] ON [financial].[StatTypeInt]
		(
			[KeyElementId] ASC,
			[InsertFlag] ASC
		)
		INCLUDE ( 	[PartitionId],
			[StatId],
			[StatValue],
			[BatchLogId]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [WORK]

		SELECT @nvMessage2 = @nvMessage + ' Create ixStatTypeInt Took '+convert(nvarchar(20),datediff(microsecond,@dt,sysdatetime()))+ ' mcs'
		WHERE @bExists = 1 
			AND @bEnableLog = 1;
		INSERT INTO [dbo].[StatLog]([Message])
		SELECT @nvMessage2
		WHERE @bExists = 1 
			AND @bEnableLog = 1;
		SET @dt = sysdatetime();

		SET @iPageNumber = 1;
		SELECT @iPageCount = CEILING((COUNT(1)/(@iPageSize*1.0))) --returns same integer, or +1 if fraction exists
		FROM [financial].[StatTypeInt]
		WHERE @bExists = 1
			AND InsertFlag = 0;

		SELECT @nvMessage2 = @nvMessage + ' Update PageCount Took '+convert(nvarchar(20),datediff(microsecond,@dt,sysdatetime()))+ ' mcs'
		WHERE @bExists = 1 
			AND @bEnableLog = 1;
		INSERT INTO [dbo].[StatLog]([Message])
		SELECT @nvMessage2
		WHERE @bExists = 1 
			AND @bEnableLog = 1;
		SET @dt = sysdatetime();

		--UPDATE only
		WHILE @bExists = 1
			AND @iPageNumber <= @iPageCount
		BEGIN	
			UPDATE dst
				SET StatValue = src.StatValue
					,BatchLogId = src.BatchLogId
			FROM [IFA].[stat].[StatTypeInt] dst
			INNER JOIN (
				SELECT PartitionId, KeyElementId, StatId, StatValue, BatchLogId, InsertFlag
				FROM [financial].[StatTypeInt] 
				WHERE InsertFlag = 0
				ORDER BY [KeyElementId] ASC
				OFFSET @iPageSize * (@iPageNumber -1) ROWS
				FETCH NEXT @iPageSize ROWS ONLY) AS src ON dst.PartitionId = src.PartitionId
														AND dst.KeyElementId = src.KeyElementId
														AND dst.StatId = src.StatId;

			SELECT @nvMessage2 = @nvMessage + ' Update dst Page:'+convert(nvarchar(20),@iPageNumber)+ ' Took '+convert(nvarchar(20),datediff(microsecond,@dt,sysdatetime()))+ ' mcs'
			WHERE @bExists = 1 
				AND @bEnableLog = 1;
			INSERT INTO [dbo].[StatLog]([Message])
			SELECT @nvMessage2
			WHERE @bExists = 1 
				AND @bEnableLog = 1;
			SET @dt = sysdatetime();

			SET @iPageNumber += 1;

			WAITFOR DELAY @ncDelay;	
		END

		SET @iPageNumber = 1;
		SELECT @iPageCount = CEILING((COUNT(1)/(@iPageSize*1.0))) --returns same integer, or +1 if fraction exists
		FROM [financial].[StatTypeInt]
		WHERE @bExists = 1
			AND InsertFlag = 1;

		SELECT @nvMessage2 = @nvMessage + ' Insert PageCount Took '+convert(nvarchar(20),datediff(microsecond,@dt,sysdatetime()))+ ' mcs'
		WHERE @bExists = 1 
			AND @bEnableLog = 1;
		INSERT INTO [dbo].[StatLog]([Message])
		SELECT @nvMessage2
		WHERE @bExists = 1 
			AND @bEnableLog = 1;
		SET @dt = sysdatetime();

		--INSERT only
		WHILE @bExists = 1
			AND @iPageNumber <= @iPageCount
		BEGIN
			INSERT INTO [IFA].[stat].[StatTypeInt](PartitionId, KeyElementId, StatId, StatValue, BatchLogId)
			SELECT  PartitionId, KeyElementId, StatId, StatValue, BatchLogId
			FROM (
				SELECT PartitionId, KeyElementId, StatId, StatValue, BatchLogId, InsertFlag
				FROM [financial].[StatTypeInt] 
				WHERE InsertFlag = 1
				ORDER BY [KeyElementId] ASC
				OFFSET @iPageSize * (@iPageNumber -1) ROWS
				FETCH NEXT @iPageSize ROWS ONLY) AS src;

			SELECT @nvMessage2 = @nvMessage + ' Insert dst Page:'+convert(nvarchar(20),@iPageNumber)+ ' Took '+convert(nvarchar(20),datediff(microsecond,@dt,sysdatetime()))+ ' mcs'
			WHERE @bExists = 1 
				AND @bEnableLog = 1;
			INSERT INTO [dbo].[StatLog]([Message])
			SELECT @nvMessage2
			WHERE @bExists = 1 
				AND @bEnableLog = 1;
			SET @dt = sysdatetime();

			SET @iPageNumber += 1;

			WAITFOR DELAY @ncDelay;
		END 
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		RETURN		
	END CATCH

	TRUNCATE TABLE [financial].[StatTypeInt];

	DROP INDEX [ixStatTypeInt] ON [financial].[StatTypeInt];

	SELECT @nvMessage2 = @nvMessage + 'Drop Index ixStatTypeInt Took '+convert(nvarchar(20),datediff(microsecond,@dt,sysdatetime()))+ ' mcs'
	WHERE @bExists = 1 
		AND @bEnableLog = 1;
	INSERT INTO [dbo].[StatLog]([Message])
	SELECT @nvMessage2
	WHERE @bExists = 1 
		AND @bEnableLog = 1;
END
