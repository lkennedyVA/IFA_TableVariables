USE [IFA]
GO
/****** Object:  StoredProcedure [command].[uspActionTypeInsertOut]    Script Date: 1/2/2025 5:50:25 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspActionTypeInsertOut
	Created By: Chris Sharp
	Description: This procedure will insert a new ActionType record

	Tables: [command].[ActionType]

	Procedures: [error].[uspLogErrorDetailUpdateOut]
   
	History:
		2018-03-30 - CBS - Created
*****************************************************************************************/
ALTER PROCEDURE [command].[uspActionTypeInsertOut](
	 @pnvActionTypeGroupCode NVARCHAR(25)
	,@pnvCode NVARCHAR(25)
	,@pnvName NVARCHAR(100)
	,@pnvDescr NVARCHAR(255)
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100)
	,@pbiActionTypeId BIGINT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblActionType TABLE (
		 ActionTypeId bigint
	);
	DECLARE @iErrorDetailId int
		,@tiActionTypeGroupId tinyint = [command].[ufnActionTypeGroup](@pnvActionTypeGroupCode)
		,@sSchemaName sysname = N'command';

	BEGIN TRY
		IF NOT EXISTS (SELECT 'X'
					FROM [command].[ActionType] 
					WHERE [Name] = @pnvName)
			AND ISNULL(@tiActionTypeGroupId, -1) <> -1
		BEGIN
			INSERT INTO [command].[ActionType] (
				 ActionTypeGroupId
				,Code
				,[Name]
				,Descr
				,StatusFlag
				,DateActivated
				,UserName
			)
			OUTPUT inserted.ActionTypeId
			INTO @tblActionType
			SELECT @tiActionTypeGroupId
				,@pnvCode
				,@pnvName 
				,@pnvDescr
				,@piStatusFlag
				,SYSDATETIME() AS DateActivated
				,@pnvUserName;

			SELECT @pbiActionTypeId = ActionTypeId 
			FROM @tblActionType;
		END
		ELSE 
		BEGIN
			RAISERROR ('ActionTypeId already exists for Name', 16, 1);
			RETURN
		END	
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @pbiActionTypeId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		THROW
	END CATCH
END
