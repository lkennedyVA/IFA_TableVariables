USE [IFA]
GO
/****** Object:  StoredProcedure [dbo].[uspVerifyOfacConsAdd]    Script Date: 1/3/2025 5:53:05 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspVerifyOfacConsAdd
	CreatedBy: Larry Dugger
	Date: 2017-08-25
	Description: This procedure will verify the 'datatypes are correct' or
		exit with an error.

	Tables: [dbo].[OfacConsAdd]

	History:
		2017-08-25 - LBD - Created
		2025-01-09 - LXK - Replaced table variable with local temp table
*****************************************************************************************/
ALTER PROCEDURE [dbo].[uspVerifyOfacConsAdd]
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #tblOfacConsAdd
	create table #tblOfacConsAdd ([EntNum] [int] NOT NULL
		,[AddNum] [int] NULL
		,[Address] [nvarchar](750) NULL
		,[CityStateProvincePostalCode] [nvarchar](116) NULL
		,[Country] [nvarchar](250) NULL
		,[Remarks] [nvarchar](200) NULL
	);
	DECLARE @iErrorDetailId int = 0
		,@sSchemaName sysname= N'utility';

	BEGIN TRY
		INSERT INTO #tblOfacConsAdd(EntNum, AddNum, [Address], CityStateProvincePostalCode, Country, Remarks)
		SELECT EntNum, AddNum, [Address], CityStateProvincePostalCode, Country, Remarks
		FROM [dbo].[OfacConsAdd]
		WHERE ISNUMERIC(EntNum) > 0
			AND ISNUMERIC(AddNum) > 0;
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		RAISERROR ('OFAC OfacConsAdd Verification Error, Import halted', 16, 1);
	END CATCH
END
