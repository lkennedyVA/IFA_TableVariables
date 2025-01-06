USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspClientAcceptedInsertOut
   CreatedBy: Larry Dugger
   Date: 2015-08-04
   Descr: This procedure will insert a new record
   Tables: [common].[ClientAccepted]
   
   Functions: [error].[uspLogErrorDetailInsertOut]
   History:
      2015-08-04 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [common].[uspClientAcceptedInsertOut](
    @pnvCode NVARCHAR(25)
   ,@pnvName NVARCHAR(50)
   ,@pnvDescr NVARCHAR(255)
   ,@piDisplayOrder INT
   ,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A' 
   ,@piClientAcceptedId INT OUTPUT
)
AS
BEGIN
   SET NOCOUNT ON;
   DECLARE @ClientAccepted table (
       ClientAcceptedId int
      ,Code nvarchar(25)
      ,Name nvarchar(50)
      ,Descr nvarchar(255)
      ,DisplayOrder int
      ,StatusFlag int
      ,DateActivated datetime2(7)
		,UserName nvarchar(100)
		);
	DECLARE @iErrorDetailId INT
      ,@iCurrentTransactionLevel INT
      ,@sSchemaName nvarchar(128);
   SET @sSchemaName = N'common';
   SET @iCurrentTransactionLevel = @@TRANCOUNT;
   BEGIN TRANSACTION
   BEGIN TRY
      INSERT INTO [common].[ClientAccepted]
         OUTPUT inserted.ClientAcceptedId
            ,inserted.Code
            ,inserted.Name
            ,inserted.Descr
            ,inserted.DisplayOrder
            ,inserted.StatusFlag
            ,inserted.DateActivated
				,inserted.UserName
         INTO @ClientAccepted
      SELECT @pnvCode
         ,@pnvName
         ,@pnvDescr
         ,@piDisplayOrder
         ,@piStatusFlag
         ,SYSDATETIME()
			,@pnvUserName; 
   END TRY
   BEGIN CATCH
      IF @@TRANCOUNT > @iCurrentTransactionLevel
         ROLLBACK TRANSACTION;
      EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
      SET @piClientAcceptedId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
   END CATCH;
   IF @@TRANCOUNT > @iCurrentTransactionLevel
   BEGIN
      COMMIT TRANSACTION;
      SELECT @piClientAcceptedId = ClientAcceptedId
      FROM @ClientAccepted
   END
END
