USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspVerifyOfacSdn
	CreatedBy: Larry Dugger
	Description: This procedure will verify the 'datatypes are correct' or
		exit with an error.

	Tables: [dbo].[OfacSdn]

	History:
		2017-08-25 - LBD - Created
		2019-06-27 - LBD - Modified, increased Program Size
		2025-01-09 - LXK - Replaced table variable with local temp table
*****************************************************************************************/
ALTER PROCEDURE [dbo].[uspVerifyOfacSdn]
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #tblOfacSdn
	create table #tblOfacSdn ([EntNum] [int] NOT NULL
		,[SdnName] [nvarchar](350) NULL
		,[SdnType] [nvarchar](12) NULL
		,[Program] [nvarchar](250) NULL
		,[Title] [nvarchar](250) NULL
		,[CallSign] [nvarchar](8) NULL
		,[VessType] [nvarchar](25) NULL
		,[Tonnage] [nvarchar](14) NULL
		,[GRT] [nvarchar](8) NULL
		,[VessFlag] [nvarchar](40) NULL
		,[VessOwner] [nvarchar](150) NULL
		,[Remarks] [nvarchar](2000) NULL
	);
	DECLARE @iErrorDetailId int = 0
		,@sSchemaName sysname= N'utility';

	BEGIN TRY
		INSERT INTO #tblOfacSdn(EntNum, SdnName, SdnType, Program, Title, CallSign, VessType, Tonnage, GRT, VessFlag, VessOwner, Remarks)
		SELECT EntNum, SdnName, SdnType, Program, Title, CallSign, VessType, Tonnage, GRT, VessFlag, VessOwner, Remarks
		FROM [dbo].[OfacSdn]
		WHERE ISNUMERIC(EntNum) > 0;
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		RAISERROR ('OFAC OfacSdn Verification Error, Import halted', 16, 1);
	END CATCH
END
