USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspLoadNewDuplicateItem 
	CreatedBy: Larry Dugger
	Date: 2017-07-12
	Description: This procedure will move records from [stat].[NewDuplicateItem]
		to [mac].[DuplicateItem]

	Tables: [mac].[DuplicateItem]
		,[stat].[NewDuplicateItem] (in Condensed database, via synonym)
		,[dbo].[DuplicateItemLog] (in Condensed database, via synonym)
	History:
		2017-07-12 - LBD - Created
		2018-05-09 - LBD - Migrated to IFA from Condensed, 
			renamed from uspDuplicateItemInsert
		2019-05-01 - LBD - Modified, uses new [mac].[DuplicateItem] table
		2019-10-09 - LBE - Modified, alter delay to 0.1 sec from 1.0 sec
		2025-01-08 - LXK - Removed table variables
*****************************************************************************************/
ALTER PROCEDURE [condensed].[uspLoadNewDuplicateItem](
	 @piPageSize INT = 1000
	,@piRecordSetSize INT = 100000
)
AS
BEGIN
	SET NOCOUNT ON; 
	DECLARE @iRowCount int = 0
		,@iRowsInserted int = 0
		,@iErrorDetailId INT
		,@sSchemaName nvarchar(128) = N'condensed';

	--THIS table holds a distinct set of rows up to @piRecordSetSize 
	drop table if exists #tblRecordSetSize
	create table #tblRecordSetSize(
		 IdMac varbinary(32) primary key
		,DateActivated date
	);
	--THIS is a PageSize of rows up to @piPageSize
	drop table if exists #tblPageSize
	create table #tblPageSize(
		 IdMac varbinary(32) primary key
		,DateActivated date
	);
	--LOAD Distinct RecordSetSize
	INSERT INTO #tblRecordSetSize(IdMac,DateActivated)
	SELECT abc.IdMac, MIN(abc.DateActivated)
	FROM (SELECT TOP (@piRecordSetSize) IdMac, CONVERT(DATE,DateActivated) as DateActivated
			FROM [stat].[NewDuplicateItem] WITH (READUNCOMMITTED) 
			ORDER BY DateActivated) abc
	GROUP BY abc.IdMac;

	IF EXISTS (SELECT 'X' FROM #tblRecordSetSize)
	BEGIN
		INSERT INTO [dbo].[DuplicateItemLog](Cnt, Msg, DateActivated)
		SELECT @piRecordSetSize,'uspDuplicateItemInsert Enter',SYSDATETIME();

		--Initially LOAD a page size of records
		INSERT INTO #tblPageSize(IdMac,DateActivated)
		SELECT TOP (@piPageSize) IdMac, DateActivated
		FROM #tblRecordSetSize;

		BEGIN TRY
			WHILE 1 = 1 --Do until we break
			BEGIN
				--2019-05-01 INSERT INTO [stat].[DuplicateItem](IdMac, DateActivated)
				INSERT INTO [mac].[DuplicateItem](IdMac, DateActivated)
				SELECT ps.IdMac
					,ps.DateActivated
				FROM #tblPageSize ps
				--2019-05-01 WHERE NOT EXISTS (SELECT 'X' FROM [stat].[DuplicateItem] WITH (READUNCOMMITTED) WHERE ps.IdMac = IdMac)
				WHERE NOT EXISTS (SELECT 'X' FROM [mac].[DuplicateItem] WHERE ps.IdMac = IdMac)

				SET @iRowsInserted += @@ROWCOUNT;

				--REMOVE what we just worked from #tblRecordSetSize
				DELETE rss
				FROM #tblRecordSetSize rss
				INNER JOIN #tblPageSize ps on rss.IdMac = ps.IdMac;

				--REMOVE what we just worked from source
				DELETE ndi
				FROM [stat].[NewDuplicateItem] ndi
				INNER JOIN #tblPageSize ps on ndi.IdMac = ps.IdMac;

				--CLEAN work table
				DELETE FROM #tblPageSize;--Clear Our Table

				--LOAD a page size of records
				INSERT INTO #tblPageSize(IdMac,DateActivated)
				SELECT TOP (@piPageSize) IdMac, DateActivated
				FROM #tblRecordSetSize;

				SET @iRowCount = @@ROWCOUNT; --establish for the next loop, if we process none, then we exit

				--IF @@ROWCOUNT = 0--WE ARE DONE --silly
				IF @iRowCount = 0--NOW We are done --2017-08-26 LBD
					BREAK
				ELSE IF CONVERT(TIME,GETDATE()) BETWEEN '3:30 AM' AND '11:59 PM'
					BREAK
				WAITFOR DELAY '00:00:00.1'
			END
		END TRY
		BEGIN CATCH
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			RETURN
		END CATCH

		INSERT INTO [dbo].[DuplicateItemLog](Cnt, Msg, DateActivated)
		SELECT @iRowsInserted,'uspDuplicateItemInsert Exit',SYSDATETIME();
	END
END
