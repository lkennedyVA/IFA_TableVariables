USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspVerifyOfacConsAlt
	CreatedBy: Larry Dugger
	Date: 2017-08-25
	Description: This procedure will verify the 'datatypes are correct' or
		exit with an error.

	Tables: [dbo].[OfacConsAlt]

	History:
		2017-08-25 - LBD - Created
		2025-01-09 - LXK - Replaced table variable with local temp table
*****************************************************************************************/
ALTER PROCEDURE [dbo].[uspVerifyOfacConsAlt]
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #tblOfacconsAlt
	create table #tblOfacconsAlt ([EntNum] [int] NOT NULL
		,[AltNum] [int] NOT NULL
		,[AltType] [nvarchar](8) NULL
		,[AltName] [nvarchar](350) NULL
		,[Remarks] [nvarchar](200) NULL
	);
	DECLARE @iErrorDetailId int = 0
		,@sSchemaName sysname= N'utility';

	BEGIN TRY
		INSERT INTO #tblOfacconsAlt(EntNum, AltNum, AltType, AltName, Remarks)
		SELECT EntNum, AltNum, AltType, AltName, Remarks
		FROM [dbo].[OfacConsAlt]
		WHERE ISNUMERIC(EntNum) > 0
			AND ISNUMERIC(AltNum) > 0;
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		RAISERROR ('OFAC OfacConsAlt Verification Error, Import halted', 16, 1);
	END CATCH
END
