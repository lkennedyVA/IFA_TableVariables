USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspDeluxeAdoptionAlert
	Created By: Larry Dugger
	Description: Retrieve several measurements related to Transaction Processing, 
		for the preceding hour
	Tables: [ifa].[Process]
		,[ifa].[Item]
	
	History:
		2020-05-13 - LBD - Created
		2023-06-30 - CBS - VALID-1099: Replacing LDugger@validsystems.net with dbmonitoralerts@validsystems.net
****************************************************************************************/
ALTER   PROCEDURE [ifa].[uspDeluxeAdoptionAlert](
	@pdAdoptionTrigger DECIMAL(6,2) = 8.00
	,@pnvRecipientsList NVARCHAR(512) = 'MWilliams@validdirect.com;MRing@Validsystems.net;dbmonitoralerts@validsystems.net'--'valid.exec@validsystems.net'
)AS
BEGIN
	SET NOCOUNT ON

	DECLARE @tblDeluxeAdoption table (Cnt int, ItemStatusId int);
	DECLARE @dtDate datetime = Getdate()	
		,@iClientAcceptedId int = [common].[ufnClientAccepted]('Accepted')
		,@nvProfileName sysname = 'SSDB-PRDTRX01'
		,@nvFrom nvarchar(4000) = 'DBSupport@ValidAdvantage.com'
		,@nvBody nvarchar(512) = 'Adoption percentage: '
		,@nvSubject nvarchar(4000) = 'Hourly Adoption Alert Deluxe - '
		,@dtStartDate datetime2(7)
		,@dtEndDate datetime2(7) = sysdatetime()
		,@dAdoptionTrigger decimal(6,1) = @pdAdoptionTrigger
		,@dAdoptionPercentage decimal(6,2);

	SET @dtStartDate = DATEADD(hour,-1,@dtEndDate);

	SET @nvSubject = @nvSubject +CONVERT(nvarchar(16),@dtStartDate,121) + ' to '+ CONVERT(nvarchar(16),@dtEndDate,121)

	INSERT INTO @tblDeluxeAdoption(Cnt,ItemStatusId)
	SELECT COUNT(*), i.ItemStatusId
	FROM [ifa].[Process] p
	INNER JOIN [ifa].[Item] i on p.ProcessId = i.Processid
	WHERE p.OrgId = 147162
		AND p.DateActivated BETWEEN @dtStartDate AND @dtEndDate
	GROUP BY i.ItemStatusId;

	IF EXISTS (SELECT'X' FROM @tblDeluxeAdoption)
	BEGIN
		SELECT @dAdoptionPercentage = (da.Cnt/sda.SumCnt) * 100 
		FROM @tblDeluxeAdoption da
		CROSS APPLY (SELECT CONVERT(DECIMAL(5,2),sum(Cnt)) as SumCnt FROM @tblDeluxeAdoption) sda
		WHERE da.ItemStatusId  = 3 --'Final'

		IF @dAdoptionPercentage < @dAdoptionTrigger
		BEGIN
			SET @nvBody += CONVERT(NVARCHAR(7),@dAdoptionPercentage)
			EXEC msdb.dbo.sp_send_dbmail 
				 @profile_name = @nvProfileName
				,@recipients = @pnvRecipientsList
				,@from_address = @nvFrom
				,@body = @nvBody
				,@subject = @nvSubject
				,@importance = 'High';
		END
	END
END
