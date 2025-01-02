USE [IFA]
GO
/****** Object:  StoredProcedure [command].[uspFieldTypeInsertOut]    Script Date: 1/2/2025 6:04:27 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspFieldTypeInsertOut
	Created By: Chris Sharp
	Description: This procedure will insert a new FieldType record

	Tables: [command].[FieldType]

	Procedures: [error].[uspLogErrorDetailUpdateOut]
   
	History:
		2018-03-30 - CBS - Created
*****************************************************************************************/
ALTER PROCEDURE [command].[uspFieldTypeInsertOut](
	 @pnvName NVARCHAR(100)
	,@pnvType NVARCHAR(100)
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100)
	,@pbiFieldTypeId BIGINT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblFieldType TABLE (
		 FieldTypeId bigint
	);
	DECLARE @iErrorDetailId int
		,@sSchemaName sysname = N'command';

	BEGIN TRY
		IF NOT EXISTS (SELECT 'X'
					FROM [command].[FieldType] 
					WHERE [Name] = @pnvName)
		BEGIN
			INSERT INTO [command].[FieldType] (
				 [Name]
				,[Type]
				,StatusFlag
				,DateActivated
				,UserName
			)
			OUTPUT inserted.FieldTypeId
			INTO @tblFieldType
			SELECT @pnvName 
				,@pnvType
				,@piStatusFlag
				,SYSDATETIME() AS DateActivated
				,@pnvUserName;

			SELECT @pbiFieldTypeId = FieldTypeId 
			FROM @tblFieldType;
		END
		ELSE 
		BEGIN
			RAISERROR ('FieldTypeId already exists for Code or Name', 16, 1);
			RETURN
		END	
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @pbiFieldTypeId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		THROW
	END CATCH
END
