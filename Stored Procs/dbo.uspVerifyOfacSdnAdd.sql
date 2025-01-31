USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspVerifyOfacSdnAdd
	CreatedBy: Larry Dugger
	Date: 2017-08-25
	Description: This procedure will verify the 'datatypes are correct' or
		exit with an error.

	Tables: [dbo].[OfacSdnAdd]

	History:
		2017-08-25 - LBD - Created
		2025-01-09 - LXK - Replaced table variable with local temp table
*****************************************************************************************/
ALTER PROCEDURE [dbo].[uspVerifyOfacSdnAdd]
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #tblOfacSdnAdd
	create table #tblOfacSdnAdd ([EntNum] [int] NULL
		,[AddNum] [int] NULL
		,[Address] [nvarchar](750) NULL
		,[CityStateProvincePostalCode] [nvarchar](116) NULL
		,[Country] [nvarchar](250) NULL
		,[Remarks] [nvarchar](200) NULL
	);
	DECLARE @iErrorDetailId int = 0
		,@sSchemaName sysname= N'utility';

	BEGIN TRY
		INSERT INTO #tblOfacSdnAdd(EntNum, AddNum, [Address], CityStateProvincePostalCode, Country, Remarks)
		SELECT EntNum, AddNum, [Address], CityStateProvincePostalCode, Country, Remarks
		FROM [dbo].[OfacSdnAdd]
		WHERE ISNUMERIC(EntNum) > 0
			AND ISNUMERIC(AddNum) > 0;
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		RAISERROR ('OFAC OfacSdnAdd Verification Error, Import halted', 16, 1);
	END CATCH
END
