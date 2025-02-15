USE [IFA]
GO
/****** Object:  StoredProcedure [dbo].[uspImportOfac]    Script Date: 1/3/2025 5:51:38 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspImportOfac
	CreatedBy: Larry Dugger
	Date: 2017-08-25
	Description: This procedure will verify each of the utility tables and then 
		replace the destination tables, if there are any verification issues, it will
		exit with an error.

	Tables: [ofac].[Ofac]
		,[ofac].[OfacAdd]
		,[ofac].[OfacAlt]
		,[dbo].[OfacConsAdd]
		,[dbo].[OfacConsAlt]
		,[dbo].[OfacPrim]
		,[dbo].[OfacSdn]
		,[dbo].[OfacSdnAdd]
		,[dbo].[OfacSdnAlt]

	History:
		2017-08-25 - LBD - Created
		2025-01-13 - LXK - Replaced table variables with local temp tables
*****************************************************************************************/
ALTER PROCEDURE [dbo].[uspImportOfac]
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #tblImportOFAC
	create table #tblImportOFAC(
		OfacId int, 
		OfacTypeId int, 
		EntNum int
		);

	DECLARE @iCONSOfacTypeId int
		,@iSDNOfacTypeId int
		,@iErrorDetailId int = 0
		,@sSchemaName sysname= N'utility';

	SELECT @iCONSOfacTypeId = OfacTypeId
	FROM [ofac].[OfacType]
	WHERE Code = 'NSDN'
	SELECT @iSDNOfacTypeId = OfacTypeId
	FROM [ofac].[OfacType]
	WHERE Code = 'SDN'

	BEGIN TRY
		DELETE FROM [ofac].[Ofac];
		INSERT INTO [ofac].[Ofac](OfacTypeId, EntNum, SdnName, SdnType, Program, Title, CallSign, VessType, Tonnage, GRT, VessFlag, VessOwner, Remarks, UserName, DateActivated)
			OUTPUT inserted.OfacId
				,inserted.OfacTypeId
				,inserted.EntNum
			INTO #tblImportOFAC
		SELECT @iSDNOfacTypeId, EntNum, SdnName, SdnType, Program, Title, CallSign, VessType, Tonnage, GRT, VessFlag, VessOwner, Remarks, UserName, DateActivated
		FROM [dbo].[OfacSdn]
		WHERE ISNUMERIC(EntNum) > 0
		UNION
		SELECT @iCONSOfacTypeId, EntNum, SdnName, SdnType, Program, Title, CallSign, VessType, Tonnage, GRT, VessFlag, VessOwner, Remarks, UserName, DateActivated
		FROM [dbo].[OfacPrim]
		WHERE ISNUMERIC(EntNum) > 0;

		--NOW Add
		DELETE FROM [ofac].[OfacAdd];
		INSERT INTO [ofac].[OfacAdd](OfacId, AddNum, [Address], CityStateProvincePostalCode, Country, Remarks, UserName, DateActivated)
		SELECT b.OfacId, AddNum, [Address], CityStateProvincePostalCode, Country, Remarks, UserName, DateActivated
		FROM [dbo].[OfacSdnAdd] o
		INNER JOIN #tblImportOFAC b on o.EntNum = b.EntNum
									AND b.OfacTypeId = @iSDNOfacTypeId
		WHERE ISNUMERIC(o.EntNum) > 0
			AND ISNUMERIC(o.AddNum) > 0
		UNION
		SELECT b.OfacId, AddNum, [Address], CityStateProvincePostalCode, Country, Remarks, UserName, DateActivated
		FROM [dbo].[OfacConsAdd] o
		INNER JOIN #tblImportOFAC b on o.EntNum = b.EntNum
									AND b.OfacTypeId = @iCONSOfacTypeId
		WHERE ISNUMERIC(o.EntNum) > 0
			AND ISNUMERIC(o.AddNum) > 0;

		--NOW Alt
		DELETE FROM [ofac].[OfacAlt];
		INSERT INTO [ofac].[OfacAlt](OfacId, AltNum, AltType, AltName, Remarks, UserName, DateActivated)
		SELECT b.OfacId, AltNum, AltType, AltName, Remarks, UserName, DateActivated
		FROM [dbo].[OfacSdnAlt] o
		INNER JOIN #tblImportOFAC b on o.EntNum = b.EntNum
									AND b.OfacTypeId = @iSDNOfacTypeId
		WHERE ISNUMERIC(o.EntNum) > 0
			AND ISNUMERIC(o.AltNum) > 0
		UNION
		SELECT b.OfacId, AltNum, AltType, AltName, Remarks, UserName, DateActivated
		FROM [dbo].[OfacConsAlt] o
		INNER JOIN #tblImportOFAC b on o.EntNum = b.EntNum
									AND b.OfacTypeId = @iCONSOfacTypeId
		WHERE ISNUMERIC(o.EntNum) > 0
			AND ISNUMERIC(o.AltNum) > 0;
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		RAISERROR ('OFAC Import Error, Import halted', 16, 1);
		THROW 
	END CATCH
END
